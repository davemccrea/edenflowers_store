defmodule EdenflowersWeb.Webhooks.StripeHandler do
  @behaviour Stripe.WebhookHandler

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders
  alias Edenflowers.Orders.{Order, Workers}

  @impl true
  def handle_event(%Stripe.Event{type: "charge.succeeded"}) do
    # Charge events are handled via payment_intent.succeeded
    :ok
  end

  @impl true
  def handle_event(%Stripe.Event{type: "payment_intent.succeeded"} = event) do
    payment_intent = event.data.object

    # Re-enqueue on success: gives a second chance if enqueue failed on an
    # earlier delivery. The worker deduplicates via the unique constraint on
    # `order_id` plus the receipt_emailed_at guard.
    with {:ok, order_id} <- fetch_order_id(event),
         {:ok, _outcome} <- finalize_checkout(order_id, payment_intent),
         {:ok, _job} <- Workers.SendOrderConfirmationEmail.enqueue(%{"order_id" => order_id}) do
      :ok
    else
      error -> handle_error(error, event)
    end
  end

  @impl true
  def handle_event(%Stripe.Event{type: type} = event)
      when type in ["payment_intent.payment_failed", "payment_intent.canceled"] do
    with {:ok, order_id} <- fetch_order_id(event),
         {:ok, outcome} <- mark_payment_failed(order_id) do
      log_payment_failed(outcome, order_id, event)
      :ok
    else
      error -> handle_error(error, event)
    end
  end

  @impl true
  def handle_event(%Stripe.Event{type: type}) do
    Logger.warning("Unhandled Stripe event: #{type}")
    :ok
  end

  defp fetch_order_id(%Stripe.Event{data: %{object: %{metadata: %{"order_id" => order_id}}}})
       when is_binary(order_id) and order_id != "" do
    {:ok, order_id}
  end

  defp fetch_order_id(_event), do: {:error, :missing_order_id}

  defp finalize_checkout(order_id, payment_intent) do
    case Ash.get(Order, order_id, actor: system_actor(), load: [:grand_total]) do
      {:ok, %{state: :placed}} ->
        {:ok, :already_placed}

      {:ok, order} ->
        with :ok <- verify_payment_intent_id(payment_intent, order),
             :ok <- verify_amount(payment_intent, order) do
          place_order(order_id)
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

  defp verify_amount(%{amount_received: amount_received}, order) do
    expected_cents = StripeAPI.to_stripe_amount(order.grand_total)

    if amount_received == expected_cents do
      :ok
    else
      {:error, {:amount_mismatch, order.id, expected_cents, amount_received}}
    end
  end

  defp place_order(order_id) do
    case Orders.finalize_checkout(order_id, actor: system_actor()) do
      {:ok, order} -> {:ok, order}
      {:error, reason} -> recover_already_placed(order_id, reason)
    end
  end

  # A concurrent delivery may have placed the order between our read and write.
  defp recover_already_placed(order_id, reason) do
    case Orders.get_order_by_id(order_id, actor: system_actor()) do
      {:ok, %{state: :placed}} -> {:ok, :already_placed}
      _ -> {:error, {:payment_update_failed, order_id, reason}}
    end
  end

  defp mark_payment_failed(order_id) do
    case Orders.get_order_by_id(order_id, actor: system_actor()) do
      {:ok, %{payment_status: :paid}} -> {:ok, :already_paid}
      {:ok, order} -> update_payment_failed(order, order_id)
      {:error, reason} -> {:error, {:payment_update_failed, order_id, reason}}
    end
  end

  defp update_payment_failed(order, order_id) do
    case Orders.mark_payment_failed(order, actor: system_actor()) do
      {:ok, order} -> {:ok, order}
      {:error, reason} -> {:error, {:payment_update_failed, order_id, reason}}
    end
  end

  # A succeeded event arrived first (or was reprocessed). Don't downgrade.
  defp log_payment_failed(:already_paid, _order_id, _event), do: :ok

  defp log_payment_failed(_order, order_id, event) do
    Logger.info("Marked order #{order_id} payment as failed for Stripe #{event.type} event #{event.id}")
  end

  defp handle_error({:error, :missing_order_id}, event) do
    Logger.warning("Stripe #{event.type} event #{event.id} is missing order_id metadata")
    :ok
  end

  defp handle_error({:error, {:payment_intent_mismatch, order_id, expected_id, actual_id}}, event) do
    Logger.error(
      "Stripe #{event.type} event #{event.id}: payment_intent mismatch for order #{order_id} (expected: #{expected_id}, got: #{actual_id})"
    )

    :ok
  end

  defp handle_error({:error, {:amount_mismatch, order_id, expected_cents, actual_cents}}, event) do
    Logger.error(
      "Stripe #{event.type} event #{event.id}: amount mismatch for order #{order_id} (expected: #{expected_cents}, got: #{actual_cents})"
    )

    :ok
  end

  defp handle_error({:error, {:payment_update_failed, order_id, reason}}, event) do
    Logger.error(
      "Failed to update payment for order #{order_id} on Stripe #{event.type} event #{event.id}: #{inspect(reason)}"
    )

    :error
  end

  defp handle_error({:error, {:enqueue_failed, order_id, changeset}}, event) do
    Logger.error(
      "Failed to enqueue Oban job for order #{order_id} with Stripe #{event.type} event #{event.id}: #{inspect(changeset)}"
    )

    :error
  end
end
