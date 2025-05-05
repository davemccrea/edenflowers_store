defmodule EdenflowersWeb.Hooks.InitStore do
  use EdenflowersWeb, :live_view
  alias Edenflowers.Store.Order
  alias Phoenix.PubSub

  def on_mount(:put_locale, _params, %{"cldr_locale" => cldr_locale} = _session, socket) do
    {:ok, language_tag} = Edenflowers.Cldr.put_locale(cldr_locale)
    Edenflowers.Cldr.put_gettext_locale(language_tag)
    {:cont, socket}
  end

  def on_mount(:put_order, _params, %{"order_id" => order_id} = _session, socket) do
    order = Order.get_for_checkout!(order_id)
    {:cont, socket |> assign(order: order)}
  end

  def on_mount(:attach_hooks, _params, _session, socket) do
    if connected?(socket) do
      PubSub.subscribe(Edenflowers.PubSub, "line_item:changed:#{socket.assigns.order.id}")
    end

    {:cont, attach_hook(socket, :handle_line_item_changed, :handle_info, &handle_line_item_changed/2)}
  end

  defp handle_line_item_changed(%Phoenix.Socket.Broadcast{topic: "line_item:changed:" <> order_id}, socket) do
    order = Order.get_for_checkout!(order_id)
    {:halt, assign(socket, order: order)}
  end

  defp handle_line_item_changed(_, socket), do: {:cont, socket}
end
