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
  # reusable, so the cart stays theirs and checkout picks it up again. A Gift
  # voucher sale goes back to its own payment step, which this browser resumes.
  def index(conn, %{"id" => order_id, "redirect_status" => "failed"}) do
    conn
    |> put_flash(:error, ~t"Your payment didn't go through. Please try again or choose another payment method.")
    |> redirect(to: retry_path(order_id, conn.assigns[:current_user]))
  end

  def index(conn, %{"id" => order_id} = params) do
    conn
    |> claim_cart(order_id, params["payment_intent"])
    |> redirect(to: ~p"/order/#{order_id}")
  end

  # release_cart refuses an order that isn't this browser's cart, so a
  # cross-site link here can't empty someone's cart. A Gift voucher sale is
  # no browser's cart: the PaymentIntent Stripe returns with is what shows
  # the order is theirs.
  defp claim_cart(conn, order_id, payment_intent_id) do
    case Orders.release_cart(order_id, get_session(conn, :visitor_id), actor: conn.assigns[:current_user]) do
      {:ok, _order} -> put_session(conn, :guest_order_id, order_id)
      {:error, _error} -> claim_paid(conn, order_id, payment_intent_id)
    end
  end

  defp claim_paid(conn, order_id, payment_intent_id) when is_binary(payment_intent_id) do
    case Orders.get_order_paid_with_payment_intent(order_id, payment_intent_id, authorize?: false) do
      {:ok, _order} -> put_session(conn, :guest_order_id, order_id)
      {:error, _not_found} -> conn
    end
  end

  defp claim_paid(conn, _order_id, nil), do: conn

  defp retry_path(order_id, actor) do
    case Orders.get_order_by_id(order_id, load: [:gift_voucher_sale?], actor: actor) do
      {:ok, %{gift_voucher_sale?: true}} -> ~q"/#{language}/gift-voucher?step=payment"
      _ -> ~p"/checkout"
    end
  end
end
