defmodule EdenflowersWeb.Plugs.Maintenance do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if maintenance_mode?() do
      case bypass_action(conn) do
        :block ->
          conn
          |> Phoenix.Controller.redirect(to: "/maternity")
          |> halt()

        :allow ->
          conn

        {:set_session_and_allow, secret} ->
          put_session(conn, :maintenance_bypass, secret)
      end
    else
      conn
    end
  end

  defp maintenance_mode? do
    Application.get_env(:edenflowers, :maintenance_mode, false)
  end

  defp bypass_action(conn) do
    secret = Application.get_env(:edenflowers, :maintenance_bypass_secret)

    cond do
      conn.request_path == "/maternity" ->
        :allow

      secret != nil and conn.params["preview"] == secret ->
        {:set_session_and_allow, secret}

      secret != nil and get_session(conn, :maintenance_bypass) == secret ->
        :allow

      true ->
        :block
    end
  end
end
