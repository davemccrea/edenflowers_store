defmodule EdenflowersWeb.Hooks.PutCart do
  @moduledoc """
  Loads the current `Cart` from the session into LiveView assigns. Replaces
  the previous `PutOrder` hook for the checkout-flow session.

  The placed-order page (`OrderLive`) loads its `Order` directly from the
  URL parameter — it's a different concept from the in-flight cart and
  doesn't rely on the session `cart_id`.
  """

  use Phoenix.Component
  require Logger

  alias Edenflowers.Store.Cart

  def on_mount(:default, _params, %{"cart_id" => cart_id} = _session, socket) do
    locale = Localize.get_locale().cldr_locale_id |> to_string()
    actor = socket.assigns[:current_user]

    Cart.update_locale(cart_id, locale, actor: actor)

    cart = Cart.get_for_checkout!(cart_id, actor: actor)
    {:cont, assign(socket, cart: cart)}
  end

  def on_mount(:default, _params, _session, socket) do
    # Some flows mount before InitStore has populated the session (e.g.
    # admin pages that bypass the browser pipeline). In that case there's
    # no cart to load — leave the assign unset so the LiveView can decide
    # whether it needs one.
    {:cont, socket}
  end
end
