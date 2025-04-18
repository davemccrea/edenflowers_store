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
    order = Order.get_order_for_checkout!(order_id)
    {:cont, socket |> assign(order: order)}
  end

  def on_mount(:handle_info_hook, _params, _session, socket) do
    if connected?(socket), do: PubSub.subscribe(Edenflowers.PubSub, "order:updated:#{socket.assigns.order.id}")
    {:cont, attach_hook(socket, :handle_info_hook, :handle_info, &handler/2)}
  end

  defp handler(%Phoenix.Socket.Broadcast{topic: "order:updated:" <> order_id}, socket) do
    order = Order.get_order_for_checkout!(order_id)
    {:halt, socket |> assign(order: order)}
  end

  defp handler(_, socket), do: {:cont, socket}
end
