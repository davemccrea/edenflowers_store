defmodule EdenflowersWeb.Hooks.HandleLineItemChanged do
  @moduledoc """
  A LiveView hook that subscribes to line item change events for a given order
  and redirects home if the cart becomes empty.
  """
  use Phoenix.Component
  import Phoenix.LiveView

  alias Edenflowers.Store.Order

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Edenflowers.PubSub, "line_item:changed:#{socket.assigns.order.id}")
    end

    {:cont, attach_hook(socket, :handle_line_item_changed, :handle_info, &handle_line_item_changed/2)}
  end

  defp handle_line_item_changed(%Phoenix.Socket.Broadcast{topic: "line_item:changed:" <> order_id}, socket) do
    actor = socket.assigns[:current_user]
    order = Order.get_for_checkout!(order_id, actor: actor)

    if Enum.empty?(order.line_items) do
      Order.restart_checkout!(order, actor: actor)
      {:halt, push_navigate(socket, to: "/")}
    else
      {:halt, assign(socket, order: order)}
    end
  end

  defp handle_line_item_changed(_, socket), do: {:cont, socket}
end
