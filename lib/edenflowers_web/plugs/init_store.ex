defmodule EdenflowersWeb.Plugs.InitStore do
  @moduledoc """
  Gives the browser session a visitor_id. It keys the browser's cart, which is only opened on its first add to
  cart, and its presence on the admin overview.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    put_session(conn, :visitor_id, get_session(conn, :visitor_id) || Ecto.UUID.generate())
  end
end
