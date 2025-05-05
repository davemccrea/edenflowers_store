defmodule EdenflowersWeb.Plugs.InitStore do
  import Plug.Conn
  require Logger
  # Assuming Order.get_by_id/1 and Order.create/0 exist
  alias Edenflowers.Store.Order

  def init(opts), do: opts

  def call(conn, _opts) do
    order_id = get_session(conn, :order_id)

    # Check order_id exists in session *and* order exists
    if order_id && Order.get_by_id(order_id) do
      conn
    else
      order = Order.create!()
      put_session(conn, :order_id, order.id)
    end
  end
end
