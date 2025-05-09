defmodule EdenflowersWeb.StripeHandler do
  @behaviour Stripe.WebhookHandler
  require Logger

  @impl true
  def handle_event(%Stripe.Event{type: "payment_intent.succeeded"} = event) do
    dbg(event)
    :ok
  end

  @impl true
  def handle_event(_event), do: :ok
end
