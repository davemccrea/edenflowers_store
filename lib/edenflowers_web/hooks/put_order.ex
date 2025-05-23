defmodule EdenflowersWeb.Hooks.PutOrder do
  use Phoenix.Component
  alias Edenflowers.Store.Order

  def on_mount(:default, _params, %{"order_id" => order_id} = _session, socket) do
    {:cont, assign_new(socket, :order, fn -> Order.get_for_checkout!(order_id) end)}
  end
end
