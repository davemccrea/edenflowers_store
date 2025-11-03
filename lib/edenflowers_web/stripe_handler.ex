defmodule EdenflowersWeb.StripeHandler do
  @behaviour Stripe.WebhookHandler

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Store.Order
  alias Edenflowers.Workers.SendOrderConfirmationEmail

  @impl true
  def handle_event(%Stripe.Event{type: "charge.succeeded"} = _event) do
    # Charge events are handled via payment_intent.succeeded
    :ok
  end

  @impl true
  def handle_event(%Stripe.Event{type: "payment_intent.succeeded"} = event) do
    with {:ok, order_id} <- fetch_order_id(event),
         {:ok, _order} <- finalise_checkout(order_id),
         {:ok, _job} <- SendOrderConfirmationEmail.enqueue(%{"order_id" => order_id}) do
      :ok
    else
      {:error, :missing_order_id} ->
        Logger.warning("Stripe payment_intent.succeeded event #{event.id} is missing order_id metadata")

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
  def handle_event(%Stripe.Event{type: type} = _event) do
    Logger.warning("Unhandled Stripe event: #{type}")
    :ok
  end

  defp fetch_order_id(%Stripe.Event{data: %{object: %{metadata: %{"order_id" => order_id}}}})
       when is_binary(order_id) and order_id != "" do
    {:ok, order_id}
  end

  defp fetch_order_id(_event), do: {:error, :missing_order_id}

  defp finalise_checkout(order_id) do
    order_id
    |> Order.finalise_checkout(actor: system_actor())
    |> case do
      {:ok, order} -> {:ok, order}
      {:error, reason} -> {:error, {:payment_update_failed, order_id, reason}}
    end
  end
end
