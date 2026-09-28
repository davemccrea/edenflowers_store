defmodule Edenflowers.Payments do
  @moduledoc """
  Takes Stripe payments for orders and course bookings.

  `complete/1` is shared by the Stripe webhook and the reconciliation job, so
  either may run first or both may run. The completing actions refuse to
  complete twice, and queue the confirmation email in the same transaction.

  A PaymentIntent names what it pays for in its metadata, as `order_id` or
  `course_registration_id`. The completing actions return `AlreadyPaid` for
  something already paid and `PaymentIntentMismatch` for someone else's
  PaymentIntent. See `Edenflowers.Payments.Errors`.
  """

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Courses
  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Order
  alias Edenflowers.Payments.Errors.{AlreadyPaid, AmountMismatch, PaymentIntentMismatch}

  @metadata_keys ["order_id", "course_registration_id"]

  @doc """
  Returns the PaymentIntent client secret for an order or course booking,
  creating the PaymentIntent on first call. An order needs `grand_total`
  loaded.
  """
  def setup(%{payment_intent_id: nil} = payable, actor) do
    amount_cents = StripeAPI.to_stripe_amount(expected_amount(payable))

    case stripe_api().create_payment_intent(amount_cents, %{metadata_key(payable) => payable.id}) do
      {:ok, payment_intent} ->
        persist_payment_intent(payable, payment_intent, actor)

      {:error, reason} ->
        Logger.error("Failed to create payment intent for #{describe(payable)}: #{inspect(reason)}")
        {:error, :payment_intent_create_failed}
    end
  end

  def setup(payable, _actor) do
    case stripe_api().retrieve_payment_intent(payable) do
      {:ok, payment_intent} ->
        {:ok, payable, payment_intent.client_secret}

      {:error, reason} ->
        Logger.error("Failed to retrieve payment intent for #{describe(payable)}: #{inspect(reason)}")
        {:error, :payment_intent_retrieve_failed}
    end
  end

  @doc "Brings the order's PaymentIntent amount in line with its `grand_total`."
  def update_amount(%Order{} = order), do: stripe_api().update_payment_intent(order)

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

      case complete_payable(ref, payment_intent.id, amount_paid) do
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

  @doc "Records a failed or canceled PaymentIntent against what it was for."
  def fail(payment_intent) do
    with {:ok, {_key, id} = ref} <- find_payable(payment_intent) do
      case fail_payable(ref, payment_intent.id) do
        {:ok, :unchanged} ->
          {:ok, :unchanged}

        {:ok, record} ->
          Logger.info("Marked payment as failed for #{describe(ref)} (PaymentIntent #{payment_intent.id})")
          {:ok, record}

        {:error, error} ->
          cond do
            find_error(error, AlreadyPaid) ->
              {:ok, :unchanged}

            mismatch = find_error(error, PaymentIntentMismatch) ->
              {:error, {:payment_intent_mismatch, id, mismatch.expected, mismatch.actual}}

            true ->
              {:error, {:payment_update_failed, id, error}}
          end
      end
    end
  end

  @doc """
  Asks Stripe about an order or course booking whose webhook may have been
  missed, and completes it if its PaymentIntent succeeded.
  """
  def reconcile(payable) do
    case stripe_api().retrieve_payment_intent(payable) do
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
        stripe_api().cancel_payment_intent(payment_intent)
        Logger.error("Failed to persist payment_intent_id for #{describe(payable)}: #{inspect(reason)}")
        {:error, :payment_intent_persist_failed}
    end
  end

  defp metadata_key(%Order{}), do: "order_id"
  defp metadata_key(%CourseRegistration{}), do: "course_registration_id"

  defp expected_amount(%Order{grand_total: grand_total}), do: grand_total
  defp expected_amount(%CourseRegistration{amount: amount}), do: amount

  defp add_payment_intent_id(%Order{} = order, payment_intent_id, actor) do
    Orders.add_payment_intent_id(order, payment_intent_id, actor: actor)
  end

  # Customers never update a booking, so only the system actor may store the id.
  defp add_payment_intent_id(%CourseRegistration{} = registration, payment_intent_id, _actor) do
    Courses.add_registration_payment_intent_id(registration, payment_intent_id, actor: system_actor())
  end

  defp complete_payable({"order_id", id}, payment_intent_id, amount_paid) do
    Orders.finalize_checkout(id, payment_intent_id, %{amount_paid: amount_paid}, actor: system_actor())
  end

  defp complete_payable({"course_registration_id", id}, payment_intent_id, amount_paid) do
    Courses.confirm_registration_payment(id, payment_intent_id, %{amount_paid: amount_paid}, actor: system_actor())
  end

  defp fail_payable({"order_id", id}, payment_intent_id) do
    Orders.mark_payment_failed(id, payment_intent_id, actor: system_actor())
  end

  # An unpaid booking needs no update: its seat hold simply lapses.
  defp fail_payable({"course_registration_id", _id}, _payment_intent_id), do: {:ok, :unchanged}

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

  defp stripe_api, do: Application.get_env(:edenflowers, :stripe_api, StripeAPI)
end
