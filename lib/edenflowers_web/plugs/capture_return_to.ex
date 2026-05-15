defmodule EdenflowersWeb.Plugs.CaptureReturnTo do
  @moduledoc """
  Captures a `return_to` query parameter into the session on the way into the
  sign-in page. `EdenflowersWeb.AuthController.success/4` later reads the
  session value to send the user back where they came from.

  Only same-origin, path-only targets are accepted (see `EdenflowersWeb.ReturnTo`).
  """
  import Plug.Conn

  alias EdenflowersWeb.ReturnTo

  @sign_in_path "/sign-in"

  def init(opts), do: opts

  def call(%Plug.Conn{request_path: @sign_in_path} = conn, _opts) do
    conn = fetch_query_params(conn)

    case ReturnTo.safe_path(conn.query_params["return_to"]) do
      nil -> conn
      path -> put_session(conn, :return_to, path)
    end
  end

  def call(conn, _opts), do: conn
end
