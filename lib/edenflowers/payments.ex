defmodule Edenflowers.Payments do
  @moduledoc """
  Takes Stripe payments for orders and course bookings.

  `complete/1` is shared by the Stripe webhook and the reconciliation job, so
  either may run first or both may run. The completing actions refuse to
  complete twice, and queue the confirmation email in the same transaction.

  A PaymentIntent names what it pays for in its metadata, as `order_id` or
  `course_registration_id`. Completing returns `AlreadyPaid` for a booking
  already confirmed and `PaymentIntentMismatch` for a PaymentIntent the
  record no longer holds. See `Edenflowers.Payments.Errors`.
  """
  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  resources do
    resource Edenflowers.Payments.Payment
  end

  require Logger
  require Ash.Query
  import Edenflowers.Actors

  alias Edenflowers.Accounts
  alias Edenflowers.Accounts.User
  alias Edenflowers.Courses
  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Order
  alias Edenflowers.Payments.Errors.AlreadyPaid
  alias Edenflowers.Payments.Errors.AmountMismatch
  alias Edenflowers.Payments.Errors.PaymentIntentMismatch
  alias Edenflowers.Payments.Payment

  @metadata_keys ["order_id", "course_registration_id"]

  @doc """
  Returns the PaymentIntent client secret for an order or course booking,
  creating the PaymentIntent on first call. An order needs `balance` loaded,
  or `grand_total` at checkout, before anything has been paid.
  """
  def setup(%{payment_intent_id: nil} = payable, actor) do
    case create_payment_intent(payable, actor) do
      {:ok, payment_intent} ->
        persist_payment_intent(payable, payment_intent, actor)

      {:error, reason} ->
        Logger.error("Failed to create payment intent for #{describe(payable)}: #{inspect(reason)}")
        {:error, :payment_intent_create_failed}
    end
  end

  def setup(%Order{} = order, actor) do
    with {:ok, payment_intent} <- retrieve_payment_intent(order),
         {:ok, loaded_order} <- Ash.load(order, :subscription?, actor: system_actor()),
         {:ok, customer_id} <- saved_card_customer(loaded_order, actor) do
      if payment_intent_fits?(payment_intent, loaded_order, customer_id) do
        {:ok, order, payment_intent.client_secret}
      else
        replace_payment_intent(loaded_order, payment_intent, actor)
      end
    end
  end

  def setup(payable, _actor) do
    with {:ok, payment_intent} <- retrieve_payment_intent(payable) do
      {:ok, payable, payment_intent.client_secret}
    end
  end

  defp retrieve_payment_intent(payable) do
    case StripeAPI.impl().retrieve_payment_intent(payable) do
      {:ok, payment_intent} ->
        {:ok, payment_intent}

      {:error, reason} ->
        Logger.error("Failed to retrieve payment intent for #{describe(payable)}: #{inspect(reason)}")
        {:error, :payment_intent_retrieve_failed}
    end
  end

  defp replace_payment_intent(order, payment_intent, actor) do
    with {:ok, _cancelled} <- StripeAPI.impl().cancel_payment_intent(payment_intent),
         {:ok, _order} <-
           Orders.mark_payment_cancelled(order, payment_intent.id, actor: system_actor()),
         {:ok, order} <- Orders.get_order_for_checkout(order.id, actor: actor) do
      setup(order, actor)
    else
      {:error, reason} ->
        Logger.error("Failed to replace payment intent for #{describe(order)}: #{inspect(reason)}")
        {:error, :payment_intent_replace_failed}
    end
  end

  # A subscription cart saves its card to a Stripe Customer, so later
  # deliveries can be charged without the customer present.
  defp create_payment_intent(%Order{} = order, actor) do
    amount_cents = StripeAPI.to_stripe_amount(expected_amount(order))
    metadata = %{"order_id" => order.id}

    with {:ok, order} <- Ash.load(order, :subscription?, actor: system_actor()) do
      if order.subscription? do
        with {:ok, customer} <-
               StripeAPI.impl().create_customer(%{email: order.customer_email, name: order.customer_name}) do
          StripeAPI.impl().create_payment_intent_saving_card(amount_cents, metadata, customer.id)
        end
      else
        with {:ok, customer_id} <- saved_card_customer(order, actor) do
          create_one_off_payment_intent(amount_cents, metadata, customer_id, actor)
        end
      end
    end
  end

  defp create_payment_intent(payable, _actor) do
    StripeAPI.impl().create_payment_intent(
      StripeAPI.to_stripe_amount(expected_amount(payable)),
      %{metadata_key(payable) => payable.id},
      nil
    )
  end

  # A Customer deleted in Stripe would block every checkout for the user, so
  # forget it and let them pay without saved cards. The next checkout gives
  # them a new Customer and replaces this PaymentIntent.
  defp create_one_off_payment_intent(amount_cents, metadata, customer_id, actor) do
    case StripeAPI.impl().create_payment_intent(amount_cents, metadata, customer_id) do
      {:error, error} = result ->
        if StripeAPI.missing_customer?(error) do
          forget_stripe_customer(actor, customer_id)
          StripeAPI.impl().create_payment_intent(amount_cents, metadata, nil)
        else
          result
        end

      result ->
        result
    end
  end

  defp forget_stripe_customer(user, customer_id) do
    Logger.warning("Stripe Customer #{customer_id} of user #{user.id} no longer exists; forgetting it")

    case Accounts.forget_stripe_customer(user, actor: user) do
      {:ok, _user} -> :ok
      {:error, reason} -> Logger.error("Failed to forget Stripe Customer of user #{user.id}: #{inspect(reason)}")
    end
  end

  # The one-off PaymentIntent must carry exactly the signed-in user's Customer:
  # one opened before they signed in can't show their saved cards, and one
  # left over after they signed out would pay onto their Customer.
  # Subscriptions keep a Customer of their own.
  defp payment_intent_fits?(payment_intent, order, customer_id) do
    saves_for_subscription? = Map.get(payment_intent, :setup_future_usage) == "off_session"

    order.subscription? == saves_for_subscription? and
      (order.subscription? or Map.get(payment_intent, :customer) == customer_id)
  end

  # The Customer always comes from the signed-in actor, never from params, so
  # nobody can see or charge someone else's cards. Subscriptions keep a
  # Customer of their own, so removing a saved card can't break one.
  defp saved_card_customer(%Order{subscription?: false}, %User{} = user) do
    case Accounts.ensure_stripe_customer(user, actor: user) do
      {:ok, user} ->
        {:ok, user.stripe_customer_id}

      {:error, reason} ->
        Logger.error("Failed to get a Stripe Customer for user #{user.id}: #{inspect(reason)}")
        {:error, :stripe_customer_failed}
    end
  end

  defp saved_card_customer(_order, _actor), do: {:ok, nil}

  @doc """
  Returns the client secret of a CustomerSession that lets the Payment Element
  show, save and remove the signed-in customer's cards. Call after `setup/2`,
  which gives the user their Customer.

  Returns nil for a guest or a subscription, and when Stripe can't make one:
  saved cards are a convenience, and the customer can still type a card.
  """
  def customer_session(%Order{} = order, %User{} = user) do
    with {:ok, %{subscription?: false}} <- Ash.load(order, :subscription?, actor: system_actor()),
         {:ok, %{stripe_customer_id: customer_id}} when is_binary(customer_id) <- Ash.reload(user, actor: user) do
      case StripeAPI.impl().create_customer_session(customer_id) do
        {:ok, session} ->
          session.client_secret

        {:error, reason} ->
          if StripeAPI.missing_customer?(reason), do: forget_stripe_customer(user, customer_id)
          Logger.error("Failed to create CustomerSession for #{describe(order)}: #{inspect(reason)}")
          nil
      end
    else
      {:ok, _subscription_or_no_customer} ->
        nil

      {:error, reason} ->
        Logger.error("Failed to look up the Stripe Customer for #{describe(order)}: #{inspect(reason)}")
        nil
    end
  end

  def customer_session(_order, _guest), do: nil

  @doc """
  Brings the PaymentIntent of an order or booking, with `balance` loaded, in
  line with what it still owes.
  """
  def update_amount(payable) do
    StripeAPI.impl().update_payment_intent(
      payable.payment_intent_id,
      StripeAPI.to_stripe_amount(expected_amount(payable))
    )
  end

  @doc """
  Completes whatever a succeeded PaymentIntent paid for. Orders keep the
  amount paid and flag mismatches for follow-up. Course bookings require
  the received amount to match the amount reserved.

  Returns `{:ok, :completed}` when this call completed it, or
  `{:ok, :already_completed}`.
  """
  def complete(payment_intent) do
    with {:ok, {_key, id} = ref} <- find_payable(payment_intent) do
      amount_paid = StripeAPI.from_stripe_amount(payment_intent.amount_received)

      case complete_payable(ref, payment_intent, amount_paid, paid_with(payment_intent)) do
        :already_recorded ->
          {:ok, :already_completed}

        {:ok, _record} ->
          Logger.info(
            "Completed #{describe(ref)} for PaymentIntent #{payment_intent.id} " <>
              "(#{payment_intent.amount_received} cents)"
          )

          {:ok, :completed}

        {:error, error} ->
          cond do
            find_error(error, AlreadyPaid) ->
              {:ok, :already_completed}

            # A concurrent completion got there first. The loser sees a
            # mismatch at checkout, which clears the PaymentIntent, or the
            # unique payment_intent_id on a payment link.
            recorded?(payment_intent.id) ->
              {:ok, :already_completed}

            mismatch = find_error(error, PaymentIntentMismatch) ->
              {:error, {:payment_intent_mismatch, id, mismatch.expected, mismatch.actual}}

            mismatch = find_error(error, AmountMismatch) ->
              {:error, {:amount_mismatch, id, mismatch.expected, mismatch.actual}}

            true ->
              {:error, {:payment_update_failed, id, error}}
          end
      end
    end
  end

  @doc "Clears a canceled PaymentIntent so its order or booking can open a fresh one."
  def cancel(payment_intent) do
    with {:ok, {_key, id} = ref} <- find_payable(payment_intent) do
      case cancel_payable(ref, payment_intent.id) do
        {:ok, record} ->
          Logger.info("Cleared canceled payment for #{describe(ref)} (PaymentIntent #{payment_intent.id})")
          {:ok, record}

        {:error, error} ->
          # A PaymentIntent the order has moved on from, such as the one a
          # payment link drops when Jennie records a payment.
          if find_error(error, PaymentIntentMismatch),
            do: {:ok, :unchanged},
            else: {:error, {:payment_update_failed, id, error}}
      end
    end
  end

  @doc """
  Records a refund made in the Stripe dashboard against the order or course
  booking it paid for. Refunds not yet succeeded are left alone; Stripe sends
  `refund.updated` once a pending refund goes through.
  """
  def record_stripe_refund(%{status: "succeeded", payment_intent: payment_intent_id} = refund)
      when is_binary(payment_intent_id) do
    with {:ok, payment} <- find_payment(payment_intent_id),
         false <- refund_recorded?(refund.id),
         amount = Decimal.negate(StripeAPI.from_stripe_amount(refund.amount)),
         {:ok, record} <- record_refund_against(payment, refund.id, amount) do
      Logger.info("Recorded Stripe refund #{refund.id} of #{refund.amount} cents for #{describe(record)}")
      {:ok, :recorded}
    else
      :not_found -> {:ok, :ignored}
      true -> {:ok, :already_recorded}
      {:error, error} -> recorded_meanwhile_or_error(refund.id, error)
    end
  end

  def record_stripe_refund(_refund), do: {:ok, :ignored}

  defp record_refund_against(payment, refund_id, amount) do
    with {:ok, payment} <- Ash.load(payment, [:order, :course_registration], actor: system_actor()) do
      (payment.order || payment.course_registration)
      |> Ash.Changeset.for_update(:record_stripe_refund, %{stripe_refund_id: refund_id, amount: amount},
        actor: system_actor()
      )
      |> Ash.update()
    end
  end

  # The webhook and the order page can record the same refund at once; the
  # unique stripe_refund_id turns the loser's insert into an error.
  defp recorded_meanwhile_or_error(refund_id, error) do
    if refund_recorded?(refund_id),
      do: {:ok, :already_recorded},
      else: {:error, {:refund_record_failed, refund_id, error}}
  end

  @doc """
  Asks Stripe for the refunds on an order's or course booking's Stripe
  payments and records any whose webhook never arrived. Returns how many were
  newly recorded.
  """
  def sync_refunds(payable) do
    with {:ok, refunds_by_payment} <- stripe_refunds(payable) do
      record_refunds(refunds_by_payment)
    end
  end

  defp stripe_refunds(payable) do
    payable
    |> payments_query()
    |> Ash.Query.filter(not is_nil(payment_intent_id) and amount > 0)
    |> Ash.read!(authorize?: false)
    |> Enum.reduce_while({:ok, []}, fn payment, {:ok, acc} ->
      case StripeAPI.impl().list_refunds(payment.payment_intent_id) do
        {:ok, refunds} -> {:cont, {:ok, [{payment, refunds} | acc]}}
        error -> {:halt, error}
      end
    end)
  end

  defp record_refunds(refunds_by_payment) do
    refunds_by_payment
    |> all_refunds()
    |> Enum.reduce_while({:ok, 0}, fn refund, {:ok, recorded} ->
      case record_stripe_refund(refund) do
        {:ok, :recorded} -> {:cont, {:ok, recorded + 1}}
        {:ok, _ignored_or_already_recorded} -> {:cont, {:ok, recorded}}
        error -> {:halt, error}
      end
    end)
  end

  @doc """
  Refunds an order's or course booking's negative balance through Stripe,
  newest Stripe payment first, as far as its Stripe payments cover it.
  Refunds that succeed at once are recorded here; pending ones arrive
  through the refund webhook.

  Stripe is the source of truth for what's already been refunded: succeeded
  refunds missing from our records are recorded first, and pending ones are
  taken off what's owed, so a second click never refunds the same money twice.
  The idempotency key covers two clicks racing each other.
  """
  def refund_balance(payable) do
    refund(payable, fn payable -> Decimal.negate(payable.balance) end)
  end

  @doc """
  Refunds everything an order's customer has paid through Stripe, as
  `refund_balance/1` does, for an order that will not be made.
  """
  def refund_in_full(%Order{} = order) do
    refund(order, fn order -> order.amount_paid end)
  end

  defp refund(%resource{id: id} = payable, owed) do
    with {:ok, refunds_by_payment} <- stripe_refunds(payable),
         {:ok, _recorded} <- record_refunds(refunds_by_payment),
         {:ok, payable} <- Ash.get(resource, id, load: [:balance, :amount_paid], authorize?: false) do
      owed_cents =
        StripeAPI.to_stripe_amount(Decimal.max(owed.(payable), 0)) -
          pending_cents(refunds_by_payment)

      payment_count = payable |> payments_query() |> Ash.count!(authorize?: false)

      refunds_by_payment
      |> Enum.sort_by(fn {payment, _refunds} -> payment.paid_at end, {:desc, DateTime})
      |> refund_from(owed_cents, "#{id}-#{payment_count}", [])
    end
  end

  defp pending_cents(refunds_by_payment) do
    refunds_by_payment
    |> all_refunds()
    |> Enum.reject(&(&1.status in ["succeeded", "failed", "canceled"]))
    |> Enum.map(& &1.amount)
    |> Enum.sum()
  end

  defp all_refunds(refunds_by_payment), do: Enum.flat_map(refunds_by_payment, fn {_payment, refunds} -> refunds end)

  defp refund_from(_refunds_by_payment, left_cents, _key, refunds) when left_cents <= 0,
    do: {:ok, Enum.reverse(refunds)}

  defp refund_from([], _left_cents, _key, refunds), do: {:ok, Enum.reverse(refunds)}

  defp refund_from([{payment, existing_refunds} | rest], left_cents, key, refunds) do
    case Kernel.min(left_cents, refundable_cents(payment, existing_refunds)) do
      0 ->
        refund_from(rest, left_cents, key, refunds)

      cents ->
        with {:ok, refund} <-
               StripeAPI.impl().create_refund(
                 payment.payment_intent_id,
                 cents,
                 "refund-#{key}-#{payment.payment_intent_id}"
               ),
             {:ok, _outcome} <- record_stripe_refund(refund) do
          refund_from(rest, left_cents - cents, key, [refund | refunds])
        end
    end
  end

  defp refundable_cents(payment, refunds) do
    refunded =
      refunds
      |> Enum.reject(&(&1.status in ["failed", "canceled"]))
      |> Enum.map(& &1.amount)
      |> Enum.sum()

    Kernel.max(StripeAPI.to_stripe_amount(payment.amount) - refunded, 0)
  end

  defp payments_query(payable), do: Ash.Query.do_filter(Payment, %{parent_key(payable) => payable.id})

  @doc "The `Payment` attribute that points at an order or course registration."
  def parent_key(%Order{}), do: :order_id
  def parent_key(%CourseRegistration{}), do: :course_registration_id

  defp find_payment(payment_intent_id) do
    Payment
    |> Ash.Query.filter(payment_intent_id == ^payment_intent_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> :not_found
      result -> result
    end
  end

  defp refund_recorded?(refund_id) do
    Payment
    |> Ash.Query.filter(stripe_refund_id == ^refund_id)
    |> Ash.exists?(authorize?: false)
  end

  @doc """
  Asks Stripe about an order or course booking whose webhook may have been
  missed, and completes it if its PaymentIntent succeeded.
  """
  def reconcile(payable) do
    case StripeAPI.impl().retrieve_payment_intent(payable) do
      {:ok, %{status: "succeeded"} = payment_intent} -> complete(payment_intent)
      {:ok, _not_succeeded} -> {:ok, :not_succeeded}
      {:error, reason} -> {:error, {:payment_intent_retrieve_failed, payable.id, reason}}
    end
  end

  defp persist_payment_intent(payable, payment_intent, actor) do
    case add_payment_intent_id(payable, payment_intent.id, actor) do
      {:ok, payable} ->
        Logger.info(
          "Created PaymentIntent #{payment_intent.id} for #{describe(payable)} (#{payment_intent.amount} cents)"
        )

        {:ok, payable, payment_intent.client_secret}

      {:error, reason} ->
        StripeAPI.impl().cancel_payment_intent(payment_intent)
        Logger.error("Failed to persist payment_intent_id for #{describe(payable)}: #{inspect(reason)}")
        {:error, :payment_intent_persist_failed}
    end
  end

  defp metadata_key(%Order{}), do: "order_id"
  defp metadata_key(%CourseRegistration{}), do: "course_registration_id"

  # Checkout loads only the price; nothing is paid yet, so it is the balance.
  # A payment link loads the balance, so it charges what is still owed.
  defp expected_amount(%{balance: %Decimal{} = balance}), do: balance
  defp expected_amount(%Order{grand_total: grand_total}), do: grand_total
  defp expected_amount(%CourseRegistration{amount: amount}), do: amount

  defp add_payment_intent_id(%Order{} = order, payment_intent_id, actor) do
    Orders.add_payment_intent_id(order, payment_intent_id, actor: actor)
  end

  # Customers never update a booking, so only the system actor may store the id.
  defp add_payment_intent_id(%CourseRegistration{} = registration, payment_intent_id, _actor) do
    Courses.add_registration_payment_intent_id(registration, payment_intent_id, actor: system_actor())
  end

  # A recorded PaymentIntent is a redelivery. Otherwise a checkout payment
  # places the order, and a payment link payment, on an order already placed,
  # only records the money.
  defp complete_payable({"order_id", id}, payment_intent, amount_paid, paid_with) do
    with {:ok, order} <- Orders.get_order_by_id(id, actor: system_actor()) do
      cond do
        recorded?(payment_intent.id) ->
          :already_recorded

        order.state == :placed ->
          Orders.record_link_payment(order, payment_intent.id, %{amount_paid: amount_paid, paid_with: paid_with},
            actor: system_actor()
          )

        true ->
          Orders.finalize_checkout(
            order,
            payment_intent.id,
            %{
              amount_paid: amount_paid,
              paid_with: paid_with,
              stripe_customer_id: Map.get(payment_intent, :customer),
              stripe_payment_method_id: Map.get(payment_intent, :payment_method)
            },
            actor: system_actor()
          )
      end
    end
  end

  # As for orders: a checkout payment confirms the booking, and a payment
  # link payment, on a booking already confirmed, only records the money.
  defp complete_payable({"course_registration_id", id}, payment_intent, amount_paid, paid_with) do
    with {:ok, registration} <- Courses.get_registration_by_id(id, actor: system_actor()) do
      cond do
        recorded?(payment_intent.id) ->
          :already_recorded

        registration.status == :confirmed ->
          Courses.record_registration_link_payment(
            registration,
            payment_intent.id,
            %{amount_paid: amount_paid, paid_with: paid_with},
            actor: system_actor()
          )

        true ->
          Courses.confirm_registration_payment(
            registration,
            payment_intent.id,
            %{amount_paid: amount_paid, paid_with: paid_with},
            actor: system_actor()
          )
      end
    end
  end

  @doc """
  What paid a PaymentIntent, as `payment_method_type`, `card_brand` and
  `card_last4`, for the receipt. Only shown, so a failed lookup gives an
  empty map rather than holding up the payment.
  """
  def paid_with(%{payment_method: payment_method_id}) when is_binary(payment_method_id) do
    case StripeAPI.impl().retrieve_payment_method(payment_method_id) do
      {:ok, %{type: "card", card: %{brand: brand, last4: last4}}} ->
        %{payment_method_type: "card", card_brand: brand, card_last4: last4}

      {:ok, %{type: type}} when is_binary(type) ->
        %{payment_method_type: type}

      {:ok, _unknown} ->
        %{}

      {:error, reason} ->
        Logger.warning("Couldn't look up payment method #{payment_method_id}: #{inspect(reason)}")
        %{}
    end
  end

  def paid_with(_payment_intent), do: %{}

  @doc """
  Returns the client secret of a new SetupIntent that saves a replacement card
  to the subscription's Stripe Customer.
  """
  def setup_card_replacement(subscription) do
    with {:ok, setup_intent} <-
           StripeAPI.impl().create_setup_intent(subscription.stripe_customer_id, %{"subscription_id" => subscription.id}) do
      {:ok, setup_intent.client_secret}
    end
  end

  @doc """
  Puts the card a succeeded SetupIntent saved on the subscription named in its
  metadata, given the SetupIntent or its id. Shared by the card page's return
  URL and the `setup_intent.succeeded` webhook, so either may run first or
  both may: saving the same card again changes nothing. The actor must be
  allowed to update that subscription, so a customer can't save a card to
  someone else's from an id in a URL.
  """
  def save_subscription_card(setup_intent_id, actor) when is_binary(setup_intent_id) do
    with {:ok, setup_intent} <- StripeAPI.impl().retrieve_setup_intent(setup_intent_id) do
      save_subscription_card(setup_intent, actor)
    end
  end

  def save_subscription_card(%{status: "succeeded", metadata: %{"subscription_id" => id}} = setup_intent, actor) do
    with {:ok, subscription} <- Orders.get_subscription(id, actor: actor) do
      Orders.replace_subscription_card(subscription, setup_intent.payment_method, actor: actor)
    end
  end

  def save_subscription_card(_setup_intent, _actor), do: {:error, :not_a_saved_subscription_card}

  defp recorded?(payment_intent_id) do
    Payment
    |> Ash.Query.filter(payment_intent_id == ^payment_intent_id)
    |> Ash.exists?(authorize?: false)
  end

  defp cancel_payable({"order_id", id}, payment_intent_id) do
    Orders.mark_payment_cancelled(id, payment_intent_id, actor: system_actor())
  end

  defp cancel_payable({"course_registration_id", id}, payment_intent_id) do
    Courses.mark_registration_payment_cancelled(id, payment_intent_id, actor: system_actor())
  end

  defp find_payable(%{metadata: metadata}) when is_map(metadata) do
    Enum.find_value(@metadata_keys, {:error, :unknown_payable}, fn key ->
      case Map.get(metadata, key) do
        id when is_binary(id) and id != "" -> {:ok, {key, id}}
        _ -> nil
      end
    end)
  end

  defp find_payable(_payment_intent), do: {:error, :unknown_payable}

  defp find_error(%{errors: errors}, module), do: Enum.find(errors, &is_struct(&1, module))
  defp find_error(_error, _module), do: nil

  defp describe({key, id}), do: "#{key} #{id}"
  defp describe(payable), do: describe({metadata_key(payable), payable.id})
end
