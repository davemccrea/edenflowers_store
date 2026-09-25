defmodule Edenflowers.Orders.Payment do
  @moduledoc """
  Orchestrates Stripe payments for orders during checkout.
  """

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Order
  alias Edenflowers.Orders.Workers.SendOrderConfirmationEmail

  def setup_payment(%{payment_intent_id: nil} = order, actor) do
    case stripe_api().create_payment_intent(order) do
      {:ok, payment_intent} ->
        persist_payment_intent(order, payment_intent, actor)

      {:error, reason} ->
        Logger.error("Failed to create payment intent for order #{order.id}: #{inspect(reason)}")
        {:error, :payment_intent_create_failed}
    end
  end

  def setup_payment(order, _actor) do
    case stripe_api().retrieve_payment_intent(order) do
      {:ok, payment_intent} ->
        {:ok, order, payment_intent.client_secret}

      {:error, reason} ->
        Logger.error("Failed to retrieve payment intent for order #{order.id}: #{inspect(reason)}")
        {:error, :payment_intent_retrieve_failed}
    end
  end

  def update_payment(order), do: stripe_api().update_payment_intent(order)

  @doc """
  Places the order for a succeeded PaymentIntent and enqueues its confirmation
  email. Shared by the Stripe webhook and the reconciliation job, so either may
  run first or both may run: placing is guarded by the state machine and the
  email job is unique per order.

  Returns `{:ok, order}` when this call placed the order, or
  `{:ok, :already_placed}`.
  """
  def complete_payment(order_id, payment_intent) do
    # Enqueue even when already placed: gives a second chance if enqueue failed
    # on an earlier attempt.
    with {:ok, outcome} <- finalize_checkout(order_id, payment_intent),
         {:ok, _job} <- SendOrderConfirmationEmail.enqueue(%{"order_id" => order_id}) do
      {:ok, outcome}
    end
  end

  defp finalize_checkout(order_id, payment_intent) do
    case Ash.get(Order, order_id, actor: system_actor(), load: [:grand_total]) do
      {:ok, %{state: :placed}} ->
        Logger.info("Order #{order_id} already placed for PaymentIntent #{payment_intent.id}")
        {:ok, :already_placed}

      {:ok, order} ->
        with :ok <- verify_payment_intent_id(payment_intent, order) do
          check_amount(payment_intent, order)
          place_order(order_id, payment_intent)
        end

      {:error, reason} ->
        {:error, {:payment_update_failed, order_id, reason}}
    end
  end

  defp verify_payment_intent_id(%{id: pi_id}, order) do
    if pi_id == order.payment_intent_id do
      :ok
    else
      {:error, {:payment_intent_mismatch, order.id, order.payment_intent_id, pi_id}}
    end
  end

  # The customer has paid, so the order is placed regardless. The admin
  # orders list flags the mismatch for the florist to follow up.
  defp check_amount(%{amount_received: amount_received}, order) do
    expected_cents = StripeAPI.to_stripe_amount(order.grand_total)

    if amount_received != expected_cents do
      Logger.error(
        "Amount mismatch for order #{order.id} (expected: #{expected_cents}, got: #{amount_received}). " <>
          "Placing it anyway; the cart likely changed while payment was in flight."
      )
    end
  end

  defp place_order(order_id, payment_intent) do
    amount_paid = Decimal.div(payment_intent.amount_received, 100)

    case Orders.finalize_checkout(order_id, %{amount_paid: amount_paid}, actor: system_actor()) do
      {:ok, order} ->
        Logger.info(
          "Placed order #{order_id} for PaymentIntent #{payment_intent.id} (#{payment_intent.amount_received} cents)"
        )

        {:ok, order}

      {:error, reason} ->
        recover_already_placed(order_id, reason)
    end
  end

  # A concurrent webhook delivery or reconciliation run may have placed the
  # order between our read and write.
  defp recover_already_placed(order_id, reason) do
    case Orders.get_order_by_id(order_id, actor: system_actor()) do
      {:ok, %{state: :placed}} -> {:ok, :already_placed}
      _ -> {:error, {:payment_update_failed, order_id, reason}}
    end
  end

  defp persist_payment_intent(order, payment_intent, actor) do
    case Orders.add_payment_intent_id(order, payment_intent.id, actor: actor) do
      {:ok, order} ->
        Logger.info("Created PaymentIntent #{payment_intent.id} for order #{order.id} (#{payment_intent.amount} cents)")
        {:ok, order, payment_intent.client_secret}

      {:error, reason} ->
        stripe_api().cancel_payment_intent(payment_intent)

        Logger.error("Failed to persist payment_intent_id for order #{order.id}: #{inspect(reason)}")

        {:error, :payment_intent_persist_failed}
    end
  end

  defp stripe_api, do: Application.get_env(:edenflowers, :stripe_api, Edenflowers.External.StripeAPI)
end
