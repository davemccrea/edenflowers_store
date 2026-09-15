defmodule EdenflowersWeb.Hooks.PutOrder do
  use Phoenix.Component

  alias Edenflowers.Orders

  def on_mount(:default, _params, %{"order_id" => order_id} = _session, socket) do
    locale = Edenflowers.Format.locale()
    actor = socket.assigns[:current_user]

    Orders.update_locale(order_id, locale, actor: actor)

    order = Orders.get_order_for_checkout!(order_id, actor: actor)
    {:cont, assign(socket, order: order)}
  end
end
