defmodule EdenflowersWeb.Hooks.PutOrder do
  use Phoenix.Component
  require Logger
  alias Edenflowers.Store.Order

  def on_mount(:default, _params, %{"order_id" => order_id} = _session, socket) do
    locale = Edenflowers.Cldr.get_locale() |> Cldr.to_string()
    Order.update_locale(order_id, locale)

    order = Order.get_for_checkout!(order_id)
    {:cont, assign(socket, order: order)}
  end
end
