defmodule EdenflowersWeb.StripeHandler do
  @behaviour Stripe.WebhookHandler

  require Logger

  alias Edenflowers.Store.Order

  @impl true
  def handle_event(%Stripe.Event{type: "payment_intent.succeeded"} = event) do
    with %{data: %{object: %{metadata: %{"order_id" => order_id}}}} <- event,
         {:ok, order} <- Order.payment_received(order_id) do
      Logger.info("Payment received for order #{order.id}")
    else
      error ->
        Logger.error("Error handling payment_intent.succeeded event: #{inspect(error)}")
    end

    :ok
  end

  @impl true
  def handle_event(%Stripe.Event{type: type} = _event) do
    Logger.warning("Unhandled Stripe event of type #{type}")
    :ok
  end
end
