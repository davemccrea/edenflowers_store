defmodule EdenflowersWeb.Checkout.CheckoutCompleteController do
  @moduledoc """
  Receives Stripe's browser redirect after checkout. It preserves guest access to the order and sends failed payments back to checkout.
  """

  use EdenflowersWeb, :controller

  alias Edenflowers.Orders

  # Stripe redirects the customer here from `confirmPayment` once the payment
  # method is processed. The webhook is the source of truth for payment status,
  # so this action only forwards to the order page — which enforces its own
  # access policy on placed orders.
  #
  # A guest's access to their order comes from the cart in their session. If the
  # webhook has already placed the order, it is no longer the cart and the order
  # page grants it by its visitor_id; otherwise the cart is released below.
  #
  # A redirect-based method (MobilePay) comes back with `redirect_status=failed`
  # when the customer cancels or is declined in the app. The PaymentIntent is
  # reusable, so the cart stays theirs and checkout picks it up again.
  def index(conn, %{"redirect_status" => "failed"}) do
    conn
    |> put_flash(:error, ~t"Your payment didn't go through. Please try again or choose another payment method.")
    |> redirect(to: ~p"/checkout")
  end

  def index(conn, %{"id" => order_id}) do
    conn
    |> claim_cart(order_id)
    |> redirect(to: ~p"/order/#{order_id}")
  end

  # release_cart refuses an order that isn't this browser's cart, so a
  # cross-site link here can't empty someone's cart.
  defp claim_cart(conn, order_id) do
    case Orders.release_cart(order_id, get_session(conn, :visitor_id), actor: conn.assigns[:current_user]) do
      {:ok, _order} -> put_session(conn, :guest_order_id, order_id)
      {:error, _error} -> conn
    end
  end
end
