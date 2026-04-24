defmodule EdenflowersWeb.Hooks.HandleLineItemChanged do
  @moduledoc """
  A LiveView hook that subscribes to line item change events for a given order
  and keeps assigns.order in sync across LiveViews.
  """
  use Phoenix.Component
  import Phoenix.LiveView

  alias Edenflowers.Store.Order

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) && socket.view != EdenflowersWeb.CheckoutLive do
      Phoenix.PubSub.subscribe(Edenflowers.PubSub, "line_item:changed:#{socket.assigns.order.id}")
      {:cont, attach_hook(socket, :handle_line_item_changed, :handle_info, &handle_line_item_changed/2)}
    else
      {:cont, socket}
    end
  end

  defp handle_line_item_changed(%Phoenix.Socket.Broadcast{topic: "line_item:changed:" <> order_id}, socket) do
    actor = socket.assigns[:current_user]
    order = Order.get_for_checkout!(order_id, actor: actor)
    {:halt, assign(socket, order: order)}
  end

  defp handle_line_item_changed(_, socket), do: {:cont, socket}
end
