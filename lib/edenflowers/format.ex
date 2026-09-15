defmodule Edenflowers.Format do
  @moduledoc """
  Locale-aware formatting helpers shared across the project.
  All functions return strings formatted via CLDR for the supplied locale.
  """

  @spec locale() :: Localize.Locale.locale_id()
  def locale, do: Localize.get_locale().cldr_locale_id

  @spec currency(number | nil, Localize.Locale.locale_id()) :: String.t()
  def currency(nil, locale), do: currency(0, locale)
  def currency(amount, locale), do: Localize.Number.to_string!(amount, locale: locale, currency: :EUR)

  @doc """
  Money in an explicit currency. Accepts the lowercase currency atoms stored
  on expenses (`:eur`, `:sek`) and upcases them to the ISO codes CLDR expects.

  Returns `nil` if either the value or the currency is missing, since
  LLM-extracted expenses can leave either unset.
  """
  @spec amount(number | nil, atom | nil, Localize.Locale.locale_id()) :: String.t() | nil
  def amount(value, currency, _locale) when is_nil(value) or is_nil(currency), do: nil

  def amount(value, currency, locale) do
    iso = currency |> to_string() |> String.upcase() |> String.to_existing_atom()
    Localize.Number.to_string!(value, locale: locale, currency: iso)
  end

  @spec date(Date.t() | String.t() | nil, Localize.Locale.locale_id()) :: String.t() | nil
  def date(nil, _locale), do: nil

  def date(date, "en-GB" = locale) do
    Localize.Date.to_string!(date, locale: locale, format: "dd/MM/yyyy")
  end

  def date(date, locale) do
    Localize.Date.to_string!(date, locale: locale, format: :short)
  end

  @doc "Localized day-and-month, e.g. \"8 Jun\" / \"8 juni\". For agenda labels."
  @spec day_month(Date.t(), Localize.Locale.locale_id()) :: String.t()
  def day_month(date, locale) do
    Localize.Date.to_string!(date, locale: locale, format: "d MMM")
  end

  @doc "Localized weekday with day-and-month, e.g. \"Monday 8 Jun\" / \"måndag 8 juni\"."
  @spec weekday_day_month(Date.t(), Localize.Locale.locale_id()) :: String.t()
  def weekday_day_month(date, locale) do
    Localize.Date.to_string!(date, locale: locale, format: "EEEE d MMM")
  end

  @spec datetime(DateTime.t(), Localize.Locale.locale_id(), String.t()) :: String.t()
  def datetime(datetime, locale, time_zone \\ "Europe/Helsinki") do
    shifted = DateTime.shift_zone!(datetime, time_zone)
    {:ok, date_part} = Localize.Date.to_string(shifted, locale: locale, format: :short)
    {:ok, time_part} = Localize.Time.to_string(shifted, locale: locale, format: :short)
    "#{date_part} #{time_part}"
  end

  # `fractional_digits: 1` — default rounds 25.5% (Finnish VAT) to "26%".
  @spec percentage(number, Localize.Locale.locale_id()) :: String.t()
  def percentage(rate, locale) do
    Localize.Number.to_string!(rate, locale: locale, format: :percent, fractional_digits: 1)
  end
end
