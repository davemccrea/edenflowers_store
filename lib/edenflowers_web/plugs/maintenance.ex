defmodule EdenflowersWeb.Plugs.Maintenance do
  @moduledoc """
  Redirects traffic to the maintenance page when maintenance mode is on.

  Bypass with `?preview=<MAINTENANCE_BYPASS_SECRET>`; a session cookie keeps
  subsequent requests flowing through.
  """

  import Plug.Conn

  @maintenance_path "/maternity"
  @session_key :maintenance_bypass

  def init(opts), do: opts

  def call(conn, _opts) do
    cond do
      not maintenance_mode?() ->
        conn

      conn.request_path == @maintenance_path ->
        conn

      conn.params["preview"] == bypass_secret() ->
        put_session(conn, @session_key, bypass_secret())

      get_session(conn, @session_key) == bypass_secret() ->
        conn

      true ->
        conn
        |> Phoenix.Controller.redirect(to: @maintenance_path)
        |> halt()
    end
  end

  defp maintenance_mode?, do: Application.get_env(:edenflowers, :maintenance_mode, false)
  defp bypass_secret, do: Application.get_env(:edenflowers, :maintenance_bypass_secret)
end
