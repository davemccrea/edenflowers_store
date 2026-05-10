defmodule EdenflowersWeb.Hooks.HandleLineItemChanged do
  @moduledoc """
  A LiveView hook that subscribes to line item change events for a given order
  and keeps assigns.order in sync across LiveViews.
  """
  use Phoenix.Component
  import Phoenix.LiveView

  alias Edenflowers.Store.Order

  @checkout_states [:contact_details, :gift_options, :delivery, :payment]

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
    order = maybe_restart_checkout(order, actor)
    {:halt, assign(socket, order: order)}
  end

  defp handle_line_item_changed(_, socket), do: {:cont, socket}

  # Mirror CheckoutLive's empty-cart reset for removals from the cart drawer
  # outside the checkout page. Otherwise stale checkout fields (customer name,
  # email, gift options, etc.) survive on the order and resurface the next
  # time the customer adds items and reaches /checkout.
  defp maybe_restart_checkout(%{cart_effectively_empty?: true, state: state} = order, actor)
       when state in @checkout_states do
    Order.restart_checkout!(order, actor: actor)
    Order.get_for_checkout!(order.id, actor: actor)
  end

  defp maybe_restart_checkout(order, _actor), do: order
end
