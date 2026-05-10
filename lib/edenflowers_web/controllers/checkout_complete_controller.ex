defmodule EdenflowersWeb.CheckoutCompleteController do
  use EdenflowersWeb, :controller

  alias Edenflowers.Store.Cart

  # Stripe redirects the customer here from `confirmPayment` once the payment
  # method is processed. The webhook is the source of truth for payment status,
  # so this action only resolves the cart's order and forwards to it. The
  # order page enforces its own access policy.
  #
  # Note: the URL param is the *cart_id* (set by CheckoutLive's data-return-url
  # before the customer leaves the LiveView). We resolve it to an order via
  # Cart.order_id, set on conversion. If the webhook hasn't fired yet, we
  # bounce back to the cart so the customer doesn't see a 404.
  def index(conn, %{"id" => cart_id}) do
    actor = conn.assigns[:current_user]

    case Cart.get_by_id(cart_id, actor: actor) do
      {:ok, %{order_id: order_id}} when not is_nil(order_id) ->
        conn
        |> delete_session(:cart_id)
        |> redirect(to: ~p"/order/#{order_id}")

      _ ->
        # Webhook race: redirect back to the cart so the customer can retry.
        # InitStore will hand them a fresh cart on next request.
        redirect(conn, to: ~p"/")
    end
  end
end
