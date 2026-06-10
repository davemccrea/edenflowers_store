defmodule EdenflowersWeb.LiveUserAuth do
  @moduledoc """
  Helpers for authenticating users in LiveViews.
  """

  import Phoenix.Component
  use EdenflowersWeb, :verified_routes
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias EdenflowersWeb.ReturnTo

  def on_mount(:current_user, _params, session, socket) do
    {:cont, AshAuthentication.Phoenix.LiveSession.assign_new_resources(socket, session)}
  end

  def on_mount(:live_user_optional, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:cont, socket}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end

  def on_mount(:live_user_required, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:cont, socket}
    else
      {:halt, bounce_to_sign_in(socket)}
    end
  end

  def on_mount(:live_admin_required, _params, _session, socket) do
    if socket.assigns[:current_user] && socket.assigns.current_user.admin do
      {:cont, socket}
    else
      {:halt, bounce_to_sign_in(socket)}
    end
  end

  def on_mount(:live_no_user, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end

  # The protected page the user was trying to reach is the URL stored in
  # `connect_info[:uri]` (declared in the endpoint). Pass it as a query string
  # so `EdenflowersWeb.Plugs.CaptureReturnTo` can lift it into the session
  # when the browser follows the redirect to /sign-in.
  defp bounce_to_sign_in(socket) do
    socket
    |> Phoenix.LiveView.put_flash(:error, ~t"You must sign in to access this page.")
    |> Phoenix.LiveView.redirect(to: sign_in_redirect(socket))
  end

  defp sign_in_redirect(socket) do
    case attempted_path(socket) do
      nil -> ~p"/sign-in"
      path -> ~p"/sign-in?return_to=#{path}"
    end
  end

  defp attempted_path(socket) do
    with %URI{path: path} when is_binary(path) <- Phoenix.LiveView.get_connect_info(socket, :uri),
         path_with_query <- append_query(path, socket),
         safe when is_binary(safe) <- ReturnTo.safe_path(path_with_query) do
      safe
    else
      _ -> nil
    end
  end

  defp append_query(path, socket) do
    case Phoenix.LiveView.get_connect_info(socket, :uri) do
      %URI{query: query} when is_binary(query) and query != "" -> path <> "?" <> query
      _ -> path
    end
  end
end
