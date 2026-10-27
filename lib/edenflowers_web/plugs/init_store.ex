defmodule EdenflowersWeb.Plugs.InitStore do
  @moduledoc """
  Ensures the browser session has a checkout cart. When an old cart is placed, it keeps guest access to that order and starts a new cart.
  """

  import Plug.Conn
  alias Edenflowers.Orders

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = put_session(conn, :visitor_id, get_session(conn, :visitor_id) || Ecto.UUID.generate())
    order_id = get_session(conn, :order_id)
    actor = conn.assigns[:current_user]

    # The signed session is the proof this browser owns its cart, so the read
    # skips the policy that would hide a guest's own placed order from them.
    case order_id && Orders.get_order_by_id(order_id, authorize?: false) do
      {:ok, %{state: :placed}} ->
        conn
        |> put_session(:guest_order_id, order_id)
        |> start_cart(actor)

      {:ok, _order} ->
        conn

      _ ->
        start_cart(conn, actor)
    end
  end

  defp start_cart(conn, actor) do
    order = Orders.create_for_checkout!(actor: actor)
    put_session(conn, :order_id, order.id)
  end
end
