defmodule Edenflowers.Localize.Format do
  @moduledoc """
  Locale-aware formatting helpers shared between the order-confirmation
  email body and the PDF receipt payload. All functions return strings
  formatted via CLDR for the supplied locale.
  """

  def currency(amount, locale) do
    Localize.Number.to_string!(amount, locale: locale, currency: :EUR)
  end

  @doc """
  Like `currency/2` but for an explicit currency. Accepts the lowercase
  currency atoms stored on expenses (`:eur`, `:sek`) and upcases them to the
  ISO codes CLDR expects.
  """
  def amount(value, currency, locale) do
    iso = currency |> to_string() |> String.upcase() |> String.to_existing_atom()
    Localize.Number.to_string!(value, locale: locale, currency: iso)
  end

  def date(date, locale) do
    Localize.Date.to_string!(date, locale: locale, format: :short)
  end

  def datetime(datetime, locale, time_zone \\ "Europe/Helsinki") do
    shifted = DateTime.shift_zone!(datetime, time_zone)
    {:ok, date_part} = Localize.Date.to_string(shifted, locale: locale, format: :short)
    {:ok, time_part} = Localize.Time.to_string(shifted, locale: locale, format: :short)
    "#{date_part} #{time_part}"
  end

  # `fractional_digits: 1` — default rounds 25.5% (Finnish VAT) to "26%".
  def percentage(rate, locale) do
    Localize.Number.to_string!(rate, locale: locale, format: :percent, fractional_digits: 1)
  end
end
