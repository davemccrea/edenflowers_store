defmodule Edenflowers.Orders.Changes.CreateOccurrence do
  @moduledoc """
  Turns the Subscription's next date into an Occurrence: an ordinary Online
  Order, charged to the saved card and placed by `Payments.complete/1`, as a
  checkout payment is. Then moves the Subscription on by one interval. A
  missed date makes no order and just moves it on. A refused card
  places the order unpaid with a payment link and holds the Subscription at
  `:payment_failed` until it is paid.

  Every step can be run again. The order is looked up by its subscription
  date before one is made, the charge's idempotency key is the subscription
  and date, and a charge an earlier attempt took is completed from Stripe
  rather than made again. So when HERE or Stripe fails, the action fails, the
  job retries, and the date stays where it is.

  Money that moved but couldn't be recorded is logged as an error (ADR 0002);
  the retry, the webhook or `reconcile_payment` records it later.
  """
  use Ash.Resource.Change

  require Logger

  import Ash.Expr, only: [expr: 1]
  import Edenflowers.Actors

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Fulfillment.Availability
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Order
  alias Edenflowers.Payments

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &occur/1)
  end

  # Only while still active: a cancel or pause made while the card was being
  # charged wins, rather than being overwritten with `:payment_failed` or a
  # new date. AshOban reads the stale update as the trigger no longer
  # applying. The Occurrence stays, as one past the change cutoff does.
  defp occur(changeset) do
    subscription = changeset.data
    date = subscription.next_fulfillment_date
    changeset = Ash.Changeset.filter(changeset, expr(state == :active))

    case deliver(subscription, date) do
      :ok ->
        move_on(changeset, date)

      :payment_failed ->
        changeset
        |> move_on(date)
        |> AshStateMachine.transition_state(:payment_failed)

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end

  # Atomic, so a change Jennie makes while the card is being charged isn't
  # overwritten with what the subscription held when the job started.
  defp move_on(changeset, date) do
    Ash.Changeset.atomic_update(
      changeset,
      :next_fulfillment_date,
      expr(fragment("?::date + (? * 7)::integer", ^date, interval_weeks))
    )
  end

  defp deliver(subscription, date) do
    case find_occurrence(subscription, date) do
      {:ok, %Order{state: :placed, unpaid?: true}} -> :payment_failed
      {:ok, %Order{state: :placed}} -> :ok
      {:ok, %Order{} = order} -> pay(order, subscription)
      {:ok, nil} -> occur_unless_missed(subscription, date)
      {:error, error} -> {:error, error}
    end
  end

  # Each occurrence may move within its own schedule window, but never into the
  # next one's window. This keeps closed periods from piling up deliveries.
  defp occur_unless_missed(subscription, date) do
    with {:ok, subscription} <- Ash.load(subscription, [:user, :fulfillment_option], actor: system_actor()) do
      case first_open_day(subscription.fulfillment_option, date, subscription.interval_weeks) do
        nil ->
          Logger.error(
            "Subscription #{subscription.id} missed its delivery on #{date}: " <>
              "there was no open fulfillment date before the next scheduled date. No order was made or charged."
          )

          :ok

        fulfillment_date ->
          with {:ok, order} <- create_occurrence(subscription, date, fulfillment_date), do: pay(order, subscription)
      end
    end
  end

  defp find_occurrence(subscription, date) do
    Orders.get_occurrence(subscription.id, date,
      load: [:grand_total, :unpaid?],
      not_found_error?: false,
      actor: system_actor()
    )
  end

  defp create_occurrence(subscription, date, fulfillment_date) do
    Orders.create_occurrence(
      %{
        subscription_id: subscription.id,
        subscription_date: date,
        product_variant_id: subscription.product_variant_id,
        user_id: subscription.user_id,
        customer_name: subscription.user.name,
        customer_email: to_string(subscription.user.email),
        locale: subscription.locale,
        recipient_name: subscription.recipient_name,
        recipient_phone_number: subscription.recipient_phone_number,
        delivery_address: subscription.delivery_address,
        delivery_instructions: subscription.delivery_instructions,
        fulfillment_option_id: subscription.fulfillment_option_id,
        fulfillment_date: fulfillment_date
      },
      load: [:grand_total],
      actor: system_actor()
    )
  end

  defp first_open_day(option, date, interval_weeks) do
    now = DateTime.now!("Europe/Helsinki")

    date
    |> Stream.iterate(&Date.add(&1, 1))
    |> Enum.take(interval_weeks * 7)
    |> Enum.find(&is_nil(Availability.unavailable_reason(option, &1, now)))
  end

  defp pay(%Order{payment_intent_id: nil} = order, subscription) do
    case charge(order, subscription) do
      {:ok, payment_intent} ->
        with {:ok, order} <- keep_payment_intent(order, payment_intent) do
          place(order, payment_intent, subscription)
        end

      # Declined, or the bank wants the customer to authenticate. Stripe
      # replays this answer for the same key, so a retry lands here again.
      {:error, %Stripe.Error{code: :card_error} = error} ->
        place_unpaid(order, subscription, error.message)

      {:error, error} ->
        {:error, error}
    end
  end

  # An earlier attempt charged the card but stopped before placing the order.
  defp pay(order, subscription) do
    with {:ok, payment_intent} <- stripe_api().retrieve_payment_intent(order) do
      place(order, payment_intent, subscription)
    end
  end

  defp charge(order, subscription) do
    params = %{
      customer: subscription.stripe_customer_id,
      payment_method: subscription.stripe_payment_method_id,
      metadata: %{"order_id" => order.id}
    }

    key = "sub-#{subscription.id}-#{order.subscription_date}"

    stripe_api().charge_off_session(StripeAPI.to_stripe_amount(order.grand_total), params, key)
  end

  defp place_unpaid(order, subscription, message) do
    Logger.warning(
      "The card for subscription #{subscription.id} was refused for order #{order.id}: #{message}. " <>
        "The order is placed unpaid and the customer emailed a payment link."
    )

    with {:ok, _order} <- Orders.place_unpaid_occurrence(order, actor: system_actor()) do
      :payment_failed
    end
  end

  defp keep_payment_intent(order, payment_intent) do
    case Orders.add_payment_intent_id(order, payment_intent.id, actor: system_actor()) do
      {:ok, order} ->
        {:ok, order}

      {:error, error} ->
        report_unplaced(order, payment_intent, error)
    end
  end

  defp place(order, %{status: "requires_action"} = payment_intent, subscription) do
    place_unpaid(order, subscription, "PaymentIntent #{payment_intent.id} requires customer authentication")
  end

  defp place(order, payment_intent, _subscription), do: place(order, payment_intent)

  defp place(order, %{status: "succeeded"} = payment_intent) do
    case Payments.complete(payment_intent) do
      {:ok, _completed_or_already_completed} -> :ok
      {:error, error} -> report_unplaced(order, payment_intent, error)
    end
  end

  defp place(order, payment_intent) do
    {:error, "PaymentIntent #{payment_intent.id} for order #{order.id} is #{payment_intent.status}, not succeeded"}
  end

  defp report_unplaced(order, payment_intent, error) do
    Logger.error(
      "Order #{order.id} was charged by PaymentIntent #{payment_intent.id} for its subscription " <>
        "but could not be placed: #{inspect(error)}"
    )

    {:error, error}
  end

  defp stripe_api, do: Application.get_env(:edenflowers, :stripe_api, StripeAPI)
end
