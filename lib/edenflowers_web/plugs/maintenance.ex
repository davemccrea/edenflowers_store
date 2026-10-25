defmodule EdenflowersWeb.Plugs.Maintenance do
  @moduledoc """
  Redirects traffic to the maintenance page when maintenance mode is on,
  and away from it when maintenance mode is off.

  Signed-in admins can reach every page. Sign-in and admin paths stay reachable
  so an admin can sign in; admin routes enforce their own admin check.
  Payment links stay reachable so customers can pay custom orders.
  """

  import Plug.Conn

  @maintenance_path "/back-soon"
  @bypass_prefixes ["/admin", "/sign-in", "/sign-out", "/auth", "/pay"]

  def init(opts), do: opts

  def call(conn, _opts) do
    on_maintenance_page? = conn.request_path == @maintenance_path

    cond do
      blocks?(conn.assigns[:current_user]) and not on_maintenance_page? and not bypass?(conn) ->
        redirect(conn, @maintenance_path)

      not enabled?() and on_maintenance_page? ->
        redirect(conn, "/")

      true ->
        conn
    end
  end

  defp redirect(conn, path) do
    conn
    |> Phoenix.Controller.redirect(to: path)
    |> halt()
  end

  defp bypass?(conn) do
    Enum.any?(@bypass_prefixes, &(conn.request_path == &1 or String.starts_with?(conn.request_path, &1 <> "/")))
  end

  def blocks?(user), do: enabled?() and not match?(%{admin: true}, user)

  def enabled?, do: Application.get_env(:edenflowers, :maintenance_mode, false)
end
