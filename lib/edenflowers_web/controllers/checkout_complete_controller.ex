defmodule EdenflowersWeb.CheckoutCompleteController do
  use EdenflowersWeb, :controller

  # Stripe redirects the customer here from `confirmPayment` once the payment
  # method is processed. The webhook is the source of truth for payment status,
  # so this action only forwards to the order page — which enforces its own
  # access policy on placed orders.
  def index(conn, %{"id" => order_id}) do
    conn
    |> delete_session(:order_id)
    |> redirect(to: ~p"/order/#{order_id}")
  end
end
