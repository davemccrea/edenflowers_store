defmodule EdenflowersWeb.Hooks.HandleLineItemChanged do
  @moduledoc """
  A LiveView hook that subscribes to line item change events for the browser's cart
  and keeps assigns.order in sync across LiveViews. A page that opens the cart calls
  `subscribe/1` itself, since there was nothing to subscribe to at mount.
  """
  use Phoenix.Component
  import Phoenix.LiveView

  alias Edenflowers.Orders

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) && socket.view != EdenflowersWeb.Checkout.CheckoutLive do
      if socket.assigns.order, do: subscribe(socket.assigns.order)
      {:cont, attach_hook(socket, :handle_line_item_changed, :handle_info, &handle_line_item_changed/2)}
    else
      {:cont, socket}
    end
  end

  def subscribe(order), do: Phoenix.PubSub.subscribe(Edenflowers.PubSub, "line_item:changed:#{order.id}")

  defp handle_line_item_changed(%Phoenix.Socket.Broadcast{topic: "line_item:changed:" <> _}, socket) do
    actor = socket.assigns[:current_user]
    order = Orders.get_storefront_cart!(socket.assigns.visitor_id, actor: actor)
    {:halt, assign(socket, order: order)}
  end

  defp handle_line_item_changed(_, socket), do: {:cont, socket}
end
