defmodule Edenflowers.Cldr do
  @configured_locales ["en-GB", "sv-FI", "fi"]

  use Cldr,
    locales: @configured_locales,
    default_locale: "en-GB",
    gettext: EdenflowersWeb.Gettext,
    providers: [Cldr.Number, Cldr.DateTime, Cldr.Calendar, Cldr.Language, AshTranslation]

  def configured_locales, do: @configured_locales
end
