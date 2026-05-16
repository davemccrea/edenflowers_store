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

  defp handle_line_item_changed(
         %Phoenix.Socket.Broadcast{topic: "line_item:changed:" <> order_id, event: event, payload: payload},
         socket
       ) do
    actor = socket.assigns[:current_user]
    previous_ids = line_item_ids(socket.assigns.order)
    order = Order.get_for_checkout!(order_id, actor: actor)

    socket =
      socket
      |> assign(order: order)
      |> maybe_animate_new_line_item(event, payload, previous_ids)

    {:halt, socket}
  end

  defp handle_line_item_changed(_, socket), do: {:cont, socket}

  # The cart drawer's line-item entrance animation fires only for genuinely new
  # rows. The :add_to_cart action is an upsert configured as `create`, so its
  # `action.type` is always :create even when it takes the update path; the
  # only reliable insert-vs-update signal at this layer is whether the id was
  # already in the previously-loaded line items. If it was, the quantity bump
  # falls through to PulseOnChange and no row-level animation runs.
  defp maybe_animate_new_line_item(socket, "add_to_cart", %{data: %{id: id}}, previous_ids) do
    if id in previous_ids do
      socket
    else
      push_event(socket, "cart:item-added", %{id: id})
    end
  end

  defp maybe_animate_new_line_item(socket, _event, _payload, _previous_ids), do: socket

  defp line_item_ids(%{line_items: items}) when is_list(items), do: Enum.map(items, & &1.id)
  defp line_item_ids(_), do: []
end
