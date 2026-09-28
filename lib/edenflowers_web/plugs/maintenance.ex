defmodule EdenflowersWeb.Plugs.Maintenance do
  @moduledoc """
  Redirects traffic to the maintenance page when maintenance mode is on,
  and away from it when maintenance mode is off.
  """

  import Plug.Conn

  @maintenance_path "/back-soon"

  def init(opts), do: opts

  def call(conn, _opts) do
    on_maintenance_page? = conn.request_path == @maintenance_path

    cond do
      maintenance_mode?() and not on_maintenance_page? -> redirect(conn, @maintenance_path)
      not maintenance_mode?() and on_maintenance_page? -> redirect(conn, "/")
      true -> conn
    end
  end

  defp redirect(conn, path) do
    conn
    |> Phoenix.Controller.redirect(to: path)
    |> halt()
  end

  defp maintenance_mode?, do: Application.get_env(:edenflowers, :maintenance_mode, false)
end
