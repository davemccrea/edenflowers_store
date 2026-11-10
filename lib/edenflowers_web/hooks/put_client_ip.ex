defmodule EdenflowersWeb.Hooks.PutClientIp do
  @moduledoc """
  LiveView mount hook that assigns `:client_ip` from the session, where
  `EdenflowersWeb.Plugs.PutClientIp` stored it, so pages can pass it to
  components, which can't read the session.
  """

  use Phoenix.Component

  def on_mount(:default, _params, session, socket) do
    {:cont, assign(socket, :client_ip, session["client_ip"])}
  end
end
