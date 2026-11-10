defmodule EdenflowersWeb.Plugs.PutClientIp do
  @moduledoc """
  Puts the visitor's address in the Ash context, so the `/auth` routes'
  per-visitor rate limits on `Edenflowers.Accounts.User` can key on it, and in
  the session, which is the only way a LiveView's events can learn it.

  Production sits behind a Cloudflare Tunnel, whose peer address is the
  tunnel's own, so Cloudflare's `cf-connecting-ip` header comes first.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    ip = List.first(get_req_header(conn, "cf-connecting-ip")) || to_string(:inet.ntoa(conn.remote_ip))

    conn
    |> Ash.PlugHelpers.update_context(&Map.put(&1 || %{}, :client_ip, ip))
    |> put_client_ip_session(ip)
  end

  # Rewriting an unchanged session would send a fresh cookie with every page.
  defp put_client_ip_session(conn, ip) do
    if get_session(conn, :client_ip) == ip, do: conn, else: put_session(conn, :client_ip, ip)
  end
end
