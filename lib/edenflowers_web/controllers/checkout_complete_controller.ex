defmodule EdenflowersWeb.CheckoutCompleteController do
  use EdenflowersWeb, :controller

  def index(conn, _params) do
    order_id = get_session(conn, :order_id)

    conn
    |> delete_session(:order_id)
    |> redirect(to: ~p"/order/#{order_id}")
  end
end
