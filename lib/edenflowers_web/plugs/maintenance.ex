defmodule EdenflowersWeb.Plugs.Maintenance do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if maintenance_mode?() and not bypassed?(conn) do
      conn
      |> Phoenix.Controller.redirect(to: "/closed")
      |> halt()
    else
      conn
    end
  end

  defp maintenance_mode? do
    Application.get_env(:edenflowers, :maintenance_mode, false)
  end

  defp bypassed?(conn) do
    secret = Application.get_env(:edenflowers, :maintenance_bypass_secret)

    cond do
      conn.request_path == "/closed" ->
        true

      secret != nil and conn.params["preview"] == secret ->
        put_session(conn, :maintenance_bypass, secret)
        true

      secret != nil and get_session(conn, :maintenance_bypass) == secret ->
        true

      true ->
        false
    end
  end
end
