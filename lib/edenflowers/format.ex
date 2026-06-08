defmodule Edenflowers.Format do
  @moduledoc """
  Locale-aware value formatting. The single home for turning a domain value
  (money, date, datetime, percentage, distance, duration) into a display
  string — shared by the storefront, the admin, the order-confirmation email,
  the PDF receipt payload, and the driver route page.

  Functions take an explicit `locale` so the email/receipt can format for the
  order's captured locale rather than the request's. `money/1` is the
  storefront convenience that resolves the ambient locale itself.
  """

  use GettextSigils, backend: EdenflowersWeb.Gettext

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

  # `fractional_digits: 1` — default rounds 25.5% (Finnish VAT) to "26%".
  def percentage(rate, locale) do
    Localize.Number.to_string!(rate, locale: locale, format: :percent, fractional_digits: 1)
  end

  @doc "Metres to a kilometres string, e.g. \"2.3 km\"."
  def format_distance(metres) do
    metres
    |> Kernel./(1000)
    |> :erlang.float_to_binary(decimals: 1)
    |> then(fn d -> ~t"#{d} km" end)
  end

  @doc "A decimal kilometre value to a string, e.g. \"2.3 km\"."
  def format_distance_km(kilometres) do
    kilometres
    |> to_string()
    |> then(fn d -> ~t"#{d} km" end)
  end

  @doc "Seconds to a human duration, e.g. \"12 min\" or \"1 h 30 min\"."
  def format_duration(seconds) do
    minutes = div(seconds, 60)

    cond do
      minutes >= 60 ->
        hours = div(minutes, 60)
        remaining_minutes = rem(minutes, 60)
        ~t"#{hours} h #{remaining_minutes} min"

      true ->
        ~t"#{minutes} min"
    end
  end
end
