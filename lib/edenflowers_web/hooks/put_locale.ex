defmodule EdenflowersWeb.Hooks.PutLocale do
  @moduledoc """
  LiveView mount hook that restores the locale selected in the HTTP session.
  """

  def on_mount(:default, _params, session, socket) do
    Localize.Plug.put_locale_from_session(session, gettext: EdenflowersWeb.Gettext)
    {:cont, socket}
  end
end
