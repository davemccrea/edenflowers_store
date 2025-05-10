defmodule EdenflowersWeb.StripeHandler do
  @behaviour Stripe.WebhookHandler

  require Logger

  alias Edenflowers.Store.Order
  alias Edenflowers.Workers.SendOrderConfirmationEmail

  @impl true
  def handle_event(%Stripe.Event{type: "payment_intent.succeeded"} = event) do
    with %{data: %{object: %{metadata: %{"order_id" => order_id}}}} <- event,
         {:ok, order} <- Order.payment_received(order_id),
         changeset <- SendOrderConfirmationEmail.new(%{order_id: order.id}),
         {:ok, _job} <- Oban.insert(changeset) do
      :ok
    else
      _error ->
        :error
    end
  end

  @impl true
  def handle_event(%Stripe.Event{type: type} = _event) do
    Logger.warning("Unhandled Stripe event: #{type}")
    :ok
  end
end
