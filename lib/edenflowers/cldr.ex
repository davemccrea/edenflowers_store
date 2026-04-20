defmodule Edenflowers.Cldr do
  use Cldr,
    locales: ["en-GB", "sv-FI", "fi"],
    default_locale: "sv-FI",
    gettext: EdenflowersWeb.Gettext,
    providers: [Cldr.Number, Cldr.DateTime, Cldr.Calendar, Cldr.Language, AshTranslation]
end
