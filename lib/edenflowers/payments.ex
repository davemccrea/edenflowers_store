defmodule Edenflowers.Payments.Payable do
  @moduledoc """
  The code interfaces `Edenflowers.Payments` calls for something a customer
  pays for through Stripe. Implemented by `Edenflowers.Orders.Payable` and
  `Edenflowers.Courses.Payable`.

  `complete/3` and `fail/1` return `AlreadyPaid` for something already paid,
  and `complete/3` returns `PaymentIntentMismatch` for someone else's
  PaymentIntent. See `Edenflowers.Payments.Errors`.
  """

  @type record :: struct()

  @doc "The PaymentIntent metadata key that holds the record's id."
  @callback metadata_key() :: String.t()
  @callback expected_amount(record) :: Decimal.t()
  @callback add_payment_intent_id(record, payment_intent_id :: String.t(), actor :: term()) ::
              {:ok, record} | {:error, term()}
  @callback complete(id :: String.t(), payment_intent_id :: String.t(), amount_paid :: Decimal.t()) ::
              {:ok, record} | {:error, term()}
  @callback fail(id :: String.t(), payment_intent_id :: String.t()) ::
              {:ok, record | :unchanged} | {:error, term()}
end

defmodule Edenflowers.Payments do
  @moduledoc """
  Takes Stripe payments for orders and course bookings.

  `complete/1` is shared by the Stripe webhook and the reconciliation job, so
  either may run first or both may run. The completing actions refuse to
  complete twice, and queue the confirmation email in the same transaction.
  """

  require Logger

  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders.Order
  alias Edenflowers.Payments.Errors.{AlreadyPaid, AmountMismatch, PaymentIntentMismatch}

  @adapters [Edenflowers.Orders.Payable, Edenflowers.Courses.Payable]

  @doc """
  Returns the PaymentIntent client secret for an order or course booking,
  creating the PaymentIntent on first call. An order needs `grand_total`
  loaded.
  """
  def setup(%{payment_intent_id: nil} = payable, actor) do
    adapter = adapter_for(payable)
    amount_cents = StripeAPI.to_stripe_amount(adapter.expected_amount(payable))

    case stripe_api().create_payment_intent(amount_cents, %{adapter.metadata_key() => payable.id}) do
      {:ok, payment_intent} ->
        persist_payment_intent(adapter, payable, payment_intent, actor)

      {:error, reason} ->
        Logger.error("Failed to create payment intent for #{describe(adapter, payable.id)}: #{inspect(reason)}")
        {:error, :payment_intent_create_failed}
    end
  end

  def setup(payable, _actor) do
    case stripe_api().retrieve_payment_intent(payable) do
      {:ok, payment_intent} ->
        {:ok, payable, payment_intent.client_secret}

      {:error, reason} ->
        Logger.error(
          "Failed to retrieve payment intent for #{describe(adapter_for(payable), payable.id)}: #{inspect(reason)}"
        )

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
    with {:ok, adapter, id} <- find_payable(payment_intent) do
      amount_paid = Decimal.div(payment_intent.amount_received, 100)

      case adapter.complete(id, payment_intent.id, amount_paid) do
        {:ok, _record} ->
          Logger.info(
            "Completed #{describe(adapter, id)} for PaymentIntent #{payment_intent.id} " <>
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
    with {:ok, adapter, id} <- find_payable(payment_intent) do
      case adapter.fail(id, payment_intent.id) do
        {:ok, :unchanged} ->
          {:ok, :unchanged}

        {:ok, record} ->
          Logger.info("Marked payment as failed for #{describe(adapter, id)} (PaymentIntent #{payment_intent.id})")
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

  defp persist_payment_intent(adapter, payable, payment_intent, actor) do
    case adapter.add_payment_intent_id(payable, payment_intent.id, actor) do
      {:ok, payable} ->
        Logger.info(
          "Created PaymentIntent #{payment_intent.id} for #{describe(adapter, payable.id)} (#{payment_intent.amount} cents)"
        )

        {:ok, payable, payment_intent.client_secret}

      {:error, reason} ->
        stripe_api().cancel_payment_intent(payment_intent)
        Logger.error("Failed to persist payment_intent_id for #{describe(adapter, payable.id)}: #{inspect(reason)}")
        {:error, :payment_intent_persist_failed}
    end
  end

  defp find_payable(%{metadata: metadata}) when is_map(metadata) do
    Enum.find_value(@adapters, {:error, :unknown_payable}, fn adapter ->
      case Map.get(metadata, adapter.metadata_key()) do
        id when is_binary(id) and id != "" -> {:ok, adapter, id}
        _ -> nil
      end
    end)
  end

  defp find_payable(_payment_intent), do: {:error, :unknown_payable}

  defp find_error(%{errors: errors}, module), do: Enum.find(errors, &is_struct(&1, module))
  defp find_error(_error, _module), do: nil

  defp adapter_for(%Order{}), do: Edenflowers.Orders.Payable
  defp adapter_for(%CourseRegistration{}), do: Edenflowers.Courses.Payable

  defp describe(adapter, id), do: "#{adapter.metadata_key()} #{id}"

  defp stripe_api, do: Application.get_env(:edenflowers, :stripe_api, StripeAPI)
end
