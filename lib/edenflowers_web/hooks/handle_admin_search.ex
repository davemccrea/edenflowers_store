defmodule EdenflowersWeb.Hooks.HandleAdminSearch do
  @moduledoc """
  A LiveView hook that answers the admin header's search form on every admin page, navigating to
  the search page inside the live session. The form submits as an ordinary GET when LiveView isn't
  connected.
  """
  use EdenflowersWeb, :verified_routes

  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    {:cont, attach_hook(socket, :handle_admin_search, :handle_event, &handle_admin_search/3)}
  end

  defp handle_admin_search("admin_search", %{"q" => term}, socket) do
    {:halt, push_navigate(socket, to: ~p"/admin/search?#{%{q: term}}")}
  end

  defp handle_admin_search(_event, _params, socket), do: {:cont, socket}
end
