defmodule EdenflowersWeb.Webhooks.StripeHandler do
  @behaviour Stripe.WebhookHandler

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Orders
  alias Edenflowers.Orders.Workers.SendOrderConfirmationEmail

  @impl true
  def handle_event(%Stripe.Event{type: "charge.succeeded"} = _event) do
    # Charge events are handled via payment_intent.succeeded
    :ok
  end

  @impl true
  def handle_event(%Stripe.Event{type: "payment_intent.succeeded"} = event) do
    # Always re-enqueue on success: the worker has a unique constraint on
    # `order_id`, so a redelivered webhook collapses to the existing job, and a
    # prior delivery that finalized but failed to enqueue gets a second chance.
    with {:ok, order_id} <- fetch_order_id(event),
         {:ok, _outcome} <- finalize_checkout(order_id),
         {:ok, _job} <- SendOrderConfirmationEmail.enqueue(%{"order_id" => order_id}) do
      :ok
    else
      {:error, :missing_order_id} ->
        Logger.warning("Stripe #{event.type} event #{event.id} is missing order_id metadata")

        :error

      {:error, {:payment_update_failed, order_id, reason}} ->
        Logger.error(
          "Failed to mark order #{order_id} as paid for Stripe payment_intent.succeeded event #{event.id}: #{inspect(reason)}"
        )

        :error

      {:error, {:enqueue_failed, order_id, changeset}} ->
        Logger.error(
          "Failed to enqueue Oban job for order #{order_id} with Stripe payment_intent.succeeded event #{event.id}): #{inspect(changeset)}"
        )

        :error
    end
  end

  @impl true
  def handle_event(%Stripe.Event{type: type} = event)
      when type in ["payment_intent.payment_failed", "payment_intent.canceled"] do
    with {:ok, order_id} <- fetch_order_id(event),
         {:ok, outcome} <- mark_payment_failed(order_id) do
      case outcome do
        :already_paid ->
          # A succeeded event arrived first (or was reprocessed). Don't downgrade.
          :ok

        _order ->
          Logger.info("Marked order #{order_id} payment as failed for Stripe #{type} event #{event.id}")

          :ok
      end
    else
      {:error, :missing_order_id} ->
        Logger.warning("Stripe #{type} event #{event.id} is missing order_id metadata")
        :error

      {:error, {:payment_update_failed, order_id, reason}} ->
        Logger.error(
          "Failed to mark order #{order_id} as failed for Stripe #{type} event #{event.id}: #{inspect(reason)}"
        )

        :error
    end
  end

  @impl true
  def handle_event(%Stripe.Event{type: type} = _event) do
    Logger.warning("Unhandled Stripe event: #{type}")
    :ok
  end

  defp fetch_order_id(%Stripe.Event{data: %{object: %{metadata: %{"order_id" => order_id}}}})
       when is_binary(order_id) and order_id != "" do
    {:ok, order_id}
  end

  defp fetch_order_id(_event), do: {:error, :missing_order_id}

  defp finalize_checkout(order_id) do
    case Orders.get_order_by_id(order_id, actor: system_actor()) do
      {:ok, %{state: :placed}} ->
        {:ok, :already_placed}

      _ ->
        case Orders.finalize_checkout(order_id, actor: system_actor()) do
          {:ok, order} -> {:ok, order}
          {:error, reason} -> {:error, {:payment_update_failed, order_id, reason}}
        end
    end
  end

  defp mark_payment_failed(order_id) do
    case Orders.get_order_by_id(order_id, actor: system_actor()) do
      {:ok, order} -> maybe_mark_payment_failed(order, order_id)
      {:error, reason} -> {:error, {:payment_update_failed, order_id, reason}}
    end
  end

  defp maybe_mark_payment_failed(%{payment_status: :paid}, _order_id) do
    {:ok, :already_paid}
  end

  defp maybe_mark_payment_failed(order, order_id) do
    case Orders.mark_payment_failed(order, actor: system_actor()) do
      {:ok, order} -> {:ok, order}
      {:error, reason} -> {:error, {:payment_update_failed, order_id, reason}}
    end
  end
end
