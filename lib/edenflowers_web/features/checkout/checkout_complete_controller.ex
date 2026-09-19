defmodule EdenflowersWeb.Checkout.CheckoutCompleteController do
  use EdenflowersWeb, :controller

  alias Edenflowers.Orders

  # Stripe redirects the customer here from `confirmPayment` once the payment
  # method is processed. The webhook is the source of truth for payment status,
  # so this action only forwards to the order page — which enforces its own
  # access policy on placed orders.
  def index(conn, %{"id" => order_id} = params) do
    conn
    |> delete_session(:order_id)
    |> grant_guest_access(order_id, params["payment_intent"])
    |> redirect(to: ~p"/order/#{order_id}")
  end

  # Stripe appends the payment intent id to the return URL, and only the browser
  # that paid knows it — so it lets a guest see their order without signing in.
  defp grant_guest_access(conn, order_id, payment_intent_id) when is_binary(payment_intent_id) do
    case Orders.get_order_by_id(order_id, authorize?: false) do
      {:ok, %{payment_intent_id: ^payment_intent_id}} -> put_session(conn, :guest_order_id, order_id)
      _ -> conn
    end
  end

  defp grant_guest_access(conn, _order_id, _payment_intent_id), do: conn
end
