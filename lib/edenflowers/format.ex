defmodule Edenflowers.Format do
  @moduledoc """
  Locale-aware value formatting. The single home for turning a domain value
  (money, date, datetime, percentage) into a display string via CLDR — shared
  by the storefront, the admin, the order-confirmation email, and the PDF
  receipt payload.

  Functions take an explicit `locale` so the email/receipt can format for the
  order's captured locale rather than the request's. `money/1` is the
  storefront convenience that resolves the ambient locale itself.
  """

  @doc "EUR money in the ambient locale, treating a missing value as zero. For storefront prices/totals."
  def money(value), do: currency(value || 0, Localize.get_locale())

  def currency(amount, locale), do: amount(amount, :eur, locale)

  @doc """
  Money in an explicit currency. Accepts the lowercase currency atoms stored
  on expenses (`:eur`, `:sek`) and upcases them to the ISO codes CLDR expects.

  An amount needs both a value and a currency to format; returns `nil` if
  either is missing, since LLM-extracted expenses can leave either unset.
  """
  def amount(value, currency, _locale) when is_nil(value) or is_nil(currency), do: nil

  def amount(value, currency, locale) do
    iso = currency |> to_string() |> String.upcase() |> String.to_existing_atom()
    Localize.Number.to_string!(value, locale: locale, currency: iso)
  end

  def date(nil, _locale), do: nil

  def date(date, locale) do
    Localize.Date.to_string!(date, locale: locale, format: :short)
  end

  @doc "Localized day-and-month, e.g. \"8 Jun\" / \"8 juni\". For agenda labels."
  def day_month(date, locale) do
    Localize.Date.to_string!(date, locale: locale, format: "d MMM")
  end

  @doc "Localized weekday with day-and-month, e.g. \"Monday 8 Jun\" / \"måndag 8 juni\"."
  def weekday_day_month(date, locale) do
    Localize.Date.to_string!(date, locale: locale, format: "EEEE d MMM")
  end

  def datetime(datetime, locale, time_zone \\ "Europe/Helsinki") do
    shifted = DateTime.shift_zone!(datetime, time_zone)
    {:ok, date_part} = Localize.Date.to_string(shifted, locale: locale, format: :short)
    {:ok, time_part} = Localize.Time.to_string(shifted, locale: locale, format: :short)
    "#{date_part} #{time_part}"
  end

  @doc "Metres as an approximate kilometre string, e.g. `7000` -> `\"7.0 km\"`."
  def km(nil), do: nil
  def km(metres), do: "#{Float.round(metres / 1000, 1)} km"

  @doc "Seconds as approximate whole minutes, e.g. `1800` -> `\"30 min\"`."
  def minutes(nil), do: nil
  def minutes(seconds), do: "#{round(seconds / 60)} min"

  # `fractional_digits: 1` — default rounds 25.5% (Finnish VAT) to "26%".
  def percentage(rate, locale) do
    Localize.Number.to_string!(rate, locale: locale, format: :percent, fractional_digits: 1)
  end
end
