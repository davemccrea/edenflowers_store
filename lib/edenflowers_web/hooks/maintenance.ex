defmodule EdenflowersWeb.Hooks.Maintenance do
  @moduledoc """
  LiveView mount hook that enforces maintenance mode on every mount. Live
  navigation and socket reconnects never pass through
  `EdenflowersWeb.Plugs.Maintenance`, so without this a tab open when
  maintenance mode turns on could keep browsing the storefront.
  """

  use EdenflowersWeb, :verified_routes

  import Phoenix.LiveView

  alias EdenflowersWeb.Plugs.Maintenance

  def on_mount(:default, _params, _session, socket) do
    if Maintenance.blocks?(socket.assigns[:current_user]) do
      {:halt, redirect(socket, to: ~p"/back-soon")}
    else
      {:cont, socket}
    end
  end
end
