defmodule Edenflowers.Cldr do
  use Cldr,
    locales: ["en", "sv", "fi"],
    default_locale: "en",
    providers: [Cldr.Number, Cldr.DateTime, Cldr.Calendar]
end
