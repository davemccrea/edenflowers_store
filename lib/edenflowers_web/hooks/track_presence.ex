defmodule EdenflowersWeb.Hooks.TrackPresence do
  @moduledoc "Tracks only connected store LiveViews; Presence removes them when they disconnect."

  def on_mount(:default, _params, %{"visitor_id" => visitor_id}, socket) do
    if Phoenix.LiveView.connected?(socket) do
      EdenflowersWeb.Presence.track_customer(socket.assigns[:current_user], visitor_id)
    end

    {:cont, socket}
  end

  def on_mount(:default, _params, _session, socket), do: {:cont, socket}
end
