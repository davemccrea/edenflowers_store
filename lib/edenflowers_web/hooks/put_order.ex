defmodule EdenflowersWeb.Hooks.PutOrder do
  use Phoenix.Component
  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Store.Order

  def on_mount(:default, _params, %{"order_id" => order_id} = _session, socket) do
    locale = Edenflowers.Cldr.get_locale() |> Cldr.to_string()
    actor = socket.assigns[:current_user]

    Order.update_locale(order_id, locale, actor: actor)

    order = Order.get_for_checkout!(order_id, actor: actor)
    {:cont, assign(socket, order: order)}
  end
end
