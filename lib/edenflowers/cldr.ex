defmodule Edenflowers.Cldr do
  use Cldr,
    locales: ["en_GB", "sv", "fi"],
    default_locale: "en_GB",
    gettext: EdenflowersWeb.Gettext,
    providers: [Cldr.Number, Cldr.DateTime, Cldr.Calendar, Cldr.Language]
end
