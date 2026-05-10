defmodule EdenflowersWeb.Plugs.InitStore do
  @moduledoc """
  Ensures every browsing session has a `Cart` to put line items into.

  Stores `cart_id` in the session. On subsequent requests, looks the cart up
  and creates a fresh one if the previous cart no longer exists (e.g. it was
  converted into an Order, which clears `cart_id` in
  `CheckoutCompleteController`).
  """

  import Plug.Conn
  require Logger
  alias Edenflowers.Store.Cart

  def init(opts), do: opts

  def call(conn, _opts) do
    cart_id = get_session(conn, :cart_id)
    actor = conn.assigns[:current_user]

    if cart_id do
      case Cart.get_by_id(cart_id, actor: actor) do
        {:error, _} ->
          cart = Cart.create_for_checkout!(actor: actor)
          put_session(conn, :cart_id, cart.id)

        _ ->
          conn
      end
    else
      cart = Cart.create_for_checkout!(actor: actor)
      put_session(conn, :cart_id, cart.id)
    end
  end
end
