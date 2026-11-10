defmodule EdenflowersWeb.Hooks.PutLocale do
  @moduledoc """
  LiveView mount hook that restores the locale selected in the HTTP session.
  """

  def on_mount(:admin, params, session, socket) do
    session = Map.put(session, Localize.Plug.PutLocale.session_key(), Edenflowers.Locales.admin_locale(session))
    on_mount(:default, params, session, socket)
  end

  def on_mount(:default, _params, session, socket) do
    Localize.Plug.put_locale_from_session(session, gettext: EdenflowersWeb.Gettext)
    {:cont, socket}
  end
end
