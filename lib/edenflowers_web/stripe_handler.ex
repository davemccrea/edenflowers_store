defmodule EdenflowersWeb.StripeHandler do
  @behaviour Stripe.WebhookHandler

  require Logger

  alias Edenflowers.Store.Order
  alias Edenflowers.Workers.SendOrderConfirmationEmail

  @impl true
  def handle_event(%Stripe.Event{type: "payment_intent.succeeded"} = event) do
    with {:ok, order_id} <- fetch_order_id(event),
         {:ok, _order} <- mark_payment_received(order_id),
         {:ok, _job} <- enqueue_confirmation_email(order_id) do
      :ok
    else
      {:error, :missing_order_id} ->
        Logger.warning("Stripe payment_intent.succeeded event #{event.id} is missing order_id metadata")

        :ok

      {:error, {:payment_update_failed, order_id, reason}} ->
        Logger.error(
          "Failed to mark order #{order_id} as paid for Stripe payment_intent.succeeded event #{event.id}: #{inspect(reason)}"
        )

        :error

      {:error, {:enqueue_failed, order_id, reason}} ->
        Logger.error(
          "Failed to enqueue confirmation email for order #{order_id} (Stripe payment_intent.succeeded event #{event.id}): #{inspect(reason)}"
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

  defp mark_payment_received(order_id) do
    order_id
    |> Order.payment_received()
    |> case do
      {:ok, order} -> {:ok, order}
      {:error, reason} -> {:error, {:payment_update_failed, order_id, reason}}
    end
  end

  defp enqueue_confirmation_email(order_id) do
    %{"order_id" => order_id}
    |> SendOrderConfirmationEmail.new()
    |> Oban.insert()
    |> case do
      {:ok, job} -> {:ok, job}
      {:error, reason} -> {:error, {:enqueue_failed, order_id, reason}}
    end
  end
end
