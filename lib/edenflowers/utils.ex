defmodule Edenflowers.Utils do
  def format_money(value) do
    Cldr.Number.to_string!(value,
      format: :currency,
      currency: "EUR",
      locale: Cldr.get_locale()
    )
  end
end
