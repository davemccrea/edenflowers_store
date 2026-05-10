defmodule EdenflowersWeb.Hooks.HandleLineItemChanged do
  @moduledoc """
  A LiveView hook that subscribes to cart line item change events for the
  current cart and keeps `assigns.cart` in sync across LiveViews.

  CheckoutLive subscribes to the same topic itself and handles its own
  reload (it has cart-state-aware reload logic), so this hook is a no-op
  there.
  """
  use Phoenix.Component
  import Phoenix.LiveView

  alias Edenflowers.Store.Cart

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) && socket.view != EdenflowersWeb.CheckoutLive && socket.assigns[:cart] do
      Phoenix.PubSub.subscribe(Edenflowers.PubSub, "cart_line_item:changed:#{socket.assigns.cart.id}")
      {:cont, attach_hook(socket, :handle_line_item_changed, :handle_info, &handle_line_item_changed/2)}
    else
      {:cont, socket}
    end
  end

  defp handle_line_item_changed(%Phoenix.Socket.Broadcast{topic: "cart_line_item:changed:" <> cart_id}, socket) do
    actor = socket.assigns[:current_user]
    cart = Cart.get_for_checkout!(cart_id, actor: actor)
    {:halt, assign(socket, cart: cart)}
  end

  defp handle_line_item_changed(_, socket), do: {:cont, socket}
end
