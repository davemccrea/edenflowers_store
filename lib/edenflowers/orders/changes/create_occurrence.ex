defmodule Edenflowers.Orders.Changes.CreateOccurrence do
  @moduledoc """
  Turns the Subscription's next date into an Occurrence: an ordinary Online
  Order, charged to the saved card and placed by `Payments.complete/1`, as a
  checkout payment is. Then moves the Subscription on by one interval. A
  skipped or missed date makes no order and just moves it on. A refused card
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

  alias Edenflowers.Expressions.HelsinkiToday
  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Fulfillment.Availability
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Order
  alias Edenflowers.Payments

  # A closed date moves to the next open day within this many days.
  @days_to_search 28

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &occur/1)
  end

  defp occur(changeset) do
    subscription = changeset.data
    date = subscription.next_fulfillment_date

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

  # Atomic, so a skip or change Jennie makes while the card is being charged
  # isn't overwritten with what the subscription held when the job started.
  defp move_on(changeset, date) do
    changeset
    |> Ash.Changeset.atomic_update(
      :next_fulfillment_date,
      expr(fragment("?::date + (? * 7)::integer", ^date, interval_weeks))
    )
    # Ash can't cast an array expression, so it is passed to the database as it is.
    |> Ash.Changeset.atomic_update(
      :skipped_dates,
      {:atomic, expr(type(fragment("array_remove(?, ?::date)", skipped_dates, ^date), {:array, :date}))}
    )
  end

  defp deliver(subscription, date) do
    if date in subscription.skipped_dates do
      :ok
    else
      case find_occurrence(subscription, date) do
        {:ok, %Order{state: :placed, unpaid?: true}} -> :payment_failed
        {:ok, %Order{state: :placed}} -> :ok
        {:ok, %Order{} = order} -> pay(order, subscription)
        {:ok, nil} -> occur_unless_missed(subscription, date)
        {:error, error} -> {:error, error}
      end
    end
  end

  # Only when the job was down past the date. Nothing was charged, so the date
  # is dropped rather than piling several deliveries onto the next open day.
  defp occur_unless_missed(subscription, date) do
    if Date.before?(date, HelsinkiToday.today()) do
      Logger.error("Subscription #{subscription.id} missed its delivery on #{date}. No order was made or charged.")
      :ok
    else
      with {:ok, order} <- create_occurrence(subscription, date), do: pay(order, subscription)
    end
  end

  defp find_occurrence(subscription, date) do
    Orders.get_occurrence(subscription.id, date,
      load: [:grand_total, :unpaid?],
      not_found_error?: false,
      actor: system_actor()
    )
  end

  defp create_occurrence(subscription, date) do
    with {:ok, subscription} <- Ash.load(subscription, [:user, :fulfillment_option], actor: system_actor()),
         {:ok, fulfillment_date} <- first_open_day(subscription.fulfillment_option, date) do
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
  end

  defp first_open_day(option, date) do
    now = DateTime.now!("Europe/Helsinki")

    date
    |> Stream.iterate(&Date.add(&1, 1))
    |> Enum.take(@days_to_search)
    |> Enum.find(&is_nil(Availability.unavailable_reason(option, &1, now)))
    |> case do
      nil -> {:error, "#{option.name} has no open day in the #{@days_to_search} days from #{date}"}
      open_day -> {:ok, open_day}
    end
  end

  defp pay(%Order{payment_intent_id: nil} = order, subscription) do
    case charge(order, subscription) do
      {:ok, payment_intent} ->
        with {:ok, _order} <- keep_payment_intent(order, payment_intent) do
          place(order, payment_intent)
        end

      # Declined, or the bank wants the customer to authenticate. Stripe
      # replays this answer for the same key, so a retry lands here again.
      {:error, %Stripe.Error{code: :card_error} = error} ->
        place_unpaid(order, subscription, error)

      {:error, error} ->
        {:error, error}
    end
  end

  # An earlier attempt charged the card but stopped before placing the order.
  defp pay(order, _subscription) do
    with {:ok, payment_intent} <- stripe_api().retrieve_payment_intent(order) do
      place(order, payment_intent)
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

  defp place_unpaid(order, subscription, error) do
    Logger.warning(
      "The card for subscription #{subscription.id} was refused for order #{order.id}: #{error.message}. " <>
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
