defmodule EdenflowersWeb.Webhooks.StripeHandler do
  @behaviour Stripe.WebhookHandler

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Courses
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Payment

  @impl true
  def handle_event(%Stripe.Event{type: "charge.succeeded"}) do
    # Charge events are handled via payment_intent.succeeded
    :ok
  end

  @impl true
  def handle_event(
        %Stripe.Event{
          type: "payment_intent.succeeded",
          data: %{object: %{metadata: %{"course_registration_id" => registration_id}}}
        } = event
      )
      when is_binary(registration_id) and registration_id != "" do
    case Courses.Payment.complete_payment(registration_id, event.data.object) do
      {:ok, _outcome} -> :ok
      error -> handle_error(error, event)
    end
  end

  # An unpaid course booking needs no update: its seat hold simply lapses.
  def handle_event(%Stripe.Event{
        type: type,
        data: %{object: %{metadata: %{"course_registration_id" => _}}}
      })
      when type in ["payment_intent.payment_failed", "payment_intent.canceled"] do
    :ok
  end

  @impl true
  def handle_event(%Stripe.Event{type: "payment_intent.succeeded"} = event) do
    payment_intent = event.data.object

    with {:ok, order_id} <- fetch_order_id(event),
         {:ok, _outcome} <- Payment.complete_payment(order_id, payment_intent) do
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
