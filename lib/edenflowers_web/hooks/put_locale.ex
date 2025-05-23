defmodule EdenflowersWeb.Hooks.PutLocale do
  def on_mount(:default, _params, %{"cldr_locale" => cldr_locale} = _session, socket) do
    {:ok, language_tag} = Edenflowers.Cldr.put_locale(cldr_locale)
    Edenflowers.Cldr.put_gettext_locale(language_tag)
    {:cont, socket}
  end
end
