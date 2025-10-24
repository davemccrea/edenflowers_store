defmodule EdenflowersWeb.Hooks.PutOrder do
  use Phoenix.Component
  alias Edenflowers.Store.Order

  def on_mount(:default, _params, %{"order_id" => order_id} = _session, socket) do
    locale = Edenflowers.Cldr.get_locale() |> Cldr.to_string()
    Order.update_locale(order_id, locale) |> dbg()

    {:cont, assign_new(socket, :order, fn -> Order.get_for_checkout!(order_id) end)}
  end
end
