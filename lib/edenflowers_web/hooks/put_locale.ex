defmodule EdenflowersWeb.Hooks.PutLocale do
  def on_mount(:default, _params, session, socket) do
    Localize.Plug.put_locale_from_session(session, gettext: EdenflowersWeb.Gettext)
    {:cont, socket}
  end
end
