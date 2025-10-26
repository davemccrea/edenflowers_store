defmodule EdenflowersWeb.Hooks.HandleLineItemChanged do
  @moduledoc """
  A LiveView hook that subscribes to line item change events for a given order
  and updates the socket with the latest order state.

  If an order becomes empty as a result of a line item change, the order is reset.
  """
  use EdenflowersWeb, :live_view
  import Edenflowers.Actors

  alias Edenflowers.Store.Order

  @doc """
  Subscribes to PubSub events for line item changes on the current order
  and attaches the `handle_line_item_changed/2` hook.
  """
  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Edenflowers.PubSub, "line_item:changed:#{socket.assigns.order.id}")
    end

    {:cont, attach_hook(socket, :handle_line_item_changed, :handle_info, &handle_line_item_changed/2)}
  end

  defp handle_line_item_changed(%Phoenix.Socket.Broadcast{topic: "line_item:changed:" <> order_id}, socket) do
    order = Order.get_for_checkout!(order_id, actor: guest_actor())

    order =
      if Enum.empty?(order.line_items),
        do: Order.reset!(order, actor: guest_actor()),
        else: order

    {:cont, assign(socket, order: order)}
  end

  defp handle_line_item_changed(_, socket), do: {:cont, socket}
end
