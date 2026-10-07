defmodule EdenflowersWeb.Webhooks.StripeHandler do
  @behaviour Stripe.WebhookHandler

  require Logger

  alias Edenflowers.Payments

  @impl true
  def handle_event(%Stripe.Event{type: "charge.succeeded"}) do
    # Charge events are handled via payment_intent.succeeded
    :ok
  end

  @impl true
  def handle_event(%Stripe.Event{type: "payment_intent.succeeded"} = event) do
    case Payments.complete(event.data.object) do
      {:ok, _outcome} -> :ok
      error -> handle_error(error, event)
    end
  end

  @impl true
  # The customer retries on the same PaymentIntent, so there is nothing to record.
  def handle_event(%Stripe.Event{type: "payment_intent.payment_failed"}), do: :ok

  @impl true
  def handle_event(%Stripe.Event{type: "payment_intent.canceled"} = event) do
    case Payments.cancel(event.data.object) do
      {:ok, _outcome} -> :ok
      error -> handle_error(error, event)
    end
  end

  @impl true
  def handle_event(%Stripe.Event{type: type} = event) when type in ["refund.created", "refund.updated"] do
    case Payments.record_refund(event.data.object) do
      {:ok, _outcome} ->
        :ok

      # Returning :error makes Stripe retry.
      {:error, reason} ->
        Logger.error("Failed to record Stripe #{type} event #{event.id}: #{inspect(reason)}")
        :error
    end
  end

  @impl true
  def handle_event(%Stripe.Event{type: type}) do
    Logger.warning("Unhandled Stripe event: #{type}")
    :ok
  end

  defp handle_error({:error, :unknown_payable}, event) do
    Logger.warning("Stripe #{event.type} event #{event.id} has no order_id or course_registration_id metadata")
    :ok
  end

  defp handle_error({:error, {:payment_intent_mismatch, id, expected_id, actual_id}}, event) do
    Logger.error(
      "Stripe #{event.type} event #{event.id}: payment_intent mismatch for #{id} (expected: #{expected_id}, got: #{actual_id})"
    )

    :ok
  end

  defp handle_error({:error, {:amount_mismatch, id, expected, actual}}, event) do
    Logger.error(
      "Stripe #{event.type} event #{event.id}: amount mismatch for #{id} (expected: #{expected} EUR, got: #{actual} EUR)"
    )

    :ok
  end

  # Returning :error makes Stripe retry, and the action rolled back, so nothing is half-done.
  defp handle_error({:error, {:payment_update_failed, id, reason}}, event) do
    Logger.error("Failed to update payment for #{id} on Stripe #{event.type} event #{event.id}: #{inspect(reason)}")

    :error
  end
end
