defmodule EdenflowersWeb.Plugs.InitStore do
  import Plug.Conn
  require Logger
  alias Edenflowers.Store.Order

  def init(opts), do: opts

  def call(conn, _opts) do
    order_id = get_session(conn, :order_id)
    actor = conn.assigns[:current_user]

    if order_id do
      case Order.get_by_id(order_id, actor: actor) do
        {:error, _} ->
          order = Order.create_for_checkout!(actor: actor)
          put_session(conn, :order_id, order.id)

        _ ->
          conn
      end
    else
      order = Order.create_for_checkout!(actor: actor)
      put_session(conn, :order_id, order.id)
    end
  end
end
