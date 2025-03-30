defmodule Edenflowers.Cldr do
  use Cldr,
    locales: ["en", "sv", "fi"],
    default_locale: "en",
    gettext: EdenflowersWeb.Gettext,
    providers: [Cldr.Number, Cldr.DateTime, Cldr.Calendar, Cldr.Language]
end
