defmodule EdenflowersWeb.Hooks.PutLocale do
  def on_mount(:default, _params, %{"cldr_locale" => _} = session, socket) do
    Localize.Plug.put_locale_from_session(session, gettext: EdenflowersWeb.Gettext)
    {:cont, socket}
  end

  def on_mount(:default, _params, _session, socket), do: {:cont, socket}
end
