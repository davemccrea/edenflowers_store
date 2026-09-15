defmodule EdenflowersWeb.Plugs.InitStore do
  import Plug.Conn
  alias Edenflowers.Orders

  def init(opts), do: opts

  def call(conn, _opts) do
    order_id = get_session(conn, :order_id)
    actor = conn.assigns[:current_user]

    if order_id do
      case Orders.get_order_by_id(order_id, actor: actor) do
        {:ok, %{state: :placed}} ->
          order = Orders.create_for_checkout!(actor: actor)
          put_session(conn, :order_id, order.id)

        {:error, _} ->
          order = Orders.create_for_checkout!(actor: actor)
          put_session(conn, :order_id, order.id)

        _ ->
          conn
      end
    else
      order = Orders.create_for_checkout!(actor: actor)
      put_session(conn, :order_id, order.id)
    end
  end
end
