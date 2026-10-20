defmodule EdenflowersWeb.Checkout.CheckoutCompleteController do
  use EdenflowersWeb, :controller

  # Stripe redirects the customer here from `confirmPayment` once the payment
  # method is processed. The webhook is the source of truth for payment status,
  # so this action only forwards to the order page — which enforces its own
  # access policy on placed orders.
  #
  # A guest's access to their order comes from the cart in their session. If the
  # webhook has already placed the order, `InitStore` granted it on this request;
  # otherwise the cart is still here, and is claimed below.
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

  # Only the cart being completed: a cross-site link here must not empty someone's cart.
  defp claim_cart(conn, order_id) do
    if get_session(conn, :order_id) == order_id do
      conn
      |> delete_session(:order_id)
      |> put_session(:guest_order_id, order_id)
    else
      conn
    end
  end
end
