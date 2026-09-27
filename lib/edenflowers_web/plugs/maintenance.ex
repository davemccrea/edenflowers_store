defmodule EdenflowersWeb.Plugs.Maintenance do
  @moduledoc """
  Redirects traffic to the maintenance page when maintenance mode is on.
  """

  import Plug.Conn

  @maintenance_path "/back-soon"

  def init(opts), do: opts

  def call(conn, _opts) do
    if maintenance_mode?() and conn.request_path != @maintenance_path do
      conn
      |> Phoenix.Controller.redirect(to: @maintenance_path)
      |> halt()
    else
      conn
    end
  end

  defp maintenance_mode?, do: Application.get_env(:edenflowers, :maintenance_mode, false)
end
