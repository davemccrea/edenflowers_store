defmodule Edenflowers.Format do
  @moduledoc """
  Locale-aware formatting helpers shared across the project.
  All functions return strings formatted via CLDR for the supplied locale.
  """

  use GettextSigils, backend: EdenflowersWeb.Gettext

  @spec locale() :: Localize.Locale.locale_id()
  def locale, do: Localize.get_locale().cldr_locale_id

  # Card products are named for their design alone, like "Aruba". In the
  # current Gettext locale.
  def line_item_name(%{is_card: true, product_name: name}), do: ~t"#{name} card"
  def line_item_name(line_item), do: line_item.product_name

  @spec currency(number | nil, Localize.Locale.locale_id()) :: String.t()
  def currency(nil, locale), do: currency(0, locale)
  def currency(amount, locale), do: Localize.Number.to_string!(amount, locale: locale, currency: :EUR)

  @doc """
  A storefront price: whole euros drop the cents ("45 €"), anything else keeps
  them ("45,50 €"). Checkout, receipts and admin use `currency/2` instead, so
  their columns of totals line up.
  """
  @spec storefront_price(Decimal.t() | integer | nil, Localize.Locale.locale_id()) :: String.t()
  def storefront_price(nil, locale), do: storefront_price(0, locale)

  def storefront_price(amount, locale) do
    if amount |> Decimal.new() |> Decimal.integer?() do
      Localize.Number.to_string!(amount, locale: locale, currency: :EUR, fractional_digits: 0)
    else
      currency(amount, locale)
    end
  end

  @doc """
  Money in an explicit currency. Accepts the lowercase currency atoms stored
  on expenses (`:eur`, `:sek`) and upcases them to the ISO codes CLDR expects.

  Returns `nil` if either the value or the currency is missing, since
  LLM-extracted expenses can leave either unset.
  """
  @spec currency_in(number | nil, atom | nil, Localize.Locale.locale_id()) :: String.t() | nil
  def currency_in(value, currency, _locale) when is_nil(value) or is_nil(currency), do: nil

  def currency_in(value, currency, locale) do
    iso = currency |> to_string() |> String.upcase() |> String.to_existing_atom()
    Localize.Number.to_string!(value, locale: locale, currency: iso)
  end

  @doc """
  A Finnish-style numeric date in every language, e.g. "16.5.2026". Every
  customer is in Finland, so English uses the dotted form too.
  """
  @spec date(Date.t() | DateTime.t() | String.t() | nil, Localize.Locale.locale_id()) :: String.t() | nil
  def date(nil, _locale), do: nil

  def date(%DateTime{} = datetime, locale) do
    datetime
    |> DateTime.shift_zone!(Edenflowers.ShopTime.timezone())
    |> DateTime.to_date()
    |> date(locale)
  end

  def date(date, locale) do
    Localize.Date.to_string!(date, locale: locale, format: "d.M.yyyy")
  end

  @doc ~s(Localized clock time, e.g. "10:00" / "10.00".)
  @spec time(Time.t() | nil, Localize.Locale.locale_id()) :: String.t() | nil
  def time(nil, _locale), do: nil
  def time(time, locale), do: Localize.Time.to_string!(time, locale: locale, format: :short)

  @doc """
  An order's time of day, e.g. "kl. 14:00" or "kl. 14:00–15:00", or nil when
  any time will do. In the current Gettext locale, like the rest of the copy
  around it.
  """
  @spec fulfillment_time(map(), Localize.Locale.locale_id()) :: String.t() | nil
  def fulfillment_time(order, locale) do
    if time = fulfillment_time_range(order, locale), do: ~t"at #{time}"
  end

  @doc ~s(An order's time of day without the "at", e.g. "14:00–15:00", or nil when any time will do.)
  @spec fulfillment_time_range(map(), Localize.Locale.locale_id()) :: String.t() | nil
  def fulfillment_time_range(%{fulfillment_time_start: nil}, _locale), do: nil

  def fulfillment_time_range(%{fulfillment_time_start: start, fulfillment_time_end: nil}, locale),
    do: time(start, locale)

  def fulfillment_time_range(%{fulfillment_time_start: start, fulfillment_time_end: finish}, locale),
    do: "#{time(start, locale)}–#{time(finish, locale)}"

  @doc ~s(Localized delivery distance from metres, e.g. "850 m" / "3,4 km".)
  @spec distance(non_neg_integer(), Localize.Locale.locale_id()) :: String.t()
  def distance(meters, _locale) when meters < 1000, do: "#{meters} m"

  def distance(meters, locale),
    do: "#{Localize.Number.to_string!(meters / 1000, locale: locale, fractional_digits: 1)} km"

  @doc "Day and month without the year, e.g. \"8.6.\". For labels where space is short."
  @spec day_month(Date.t(), Localize.Locale.locale_id()) :: String.t()
  def day_month(date, locale), do: Localize.Date.to_string!(date, locale: locale, format: "d.M.")

  @doc "Abbreviated standalone month name, e.g. \"Jun\"."
  @spec short_month(Date.t(), Localize.Locale.locale_id()) :: String.t()
  def short_month(date, locale), do: Localize.Date.to_string!(date, locale: locale, format: "LLL")

  @doc """
  Weekday with day and month, e.g. "Monday 8.6." / "måndag 8.6." /
  "maanantai 8.6.". For labels.

  Finnish uses the standalone weekday (`cccc`): CLDR's format-context weekday is
  the essive "maanantaina", which only reads right inside a sentence.
  """
  @spec weekday_day_month(Date.t(), Localize.Locale.locale_id()) :: String.t()
  def weekday_day_month(date, locale), do: Localize.Date.to_string!(date, locale: locale, format: "cccc d.M.")

  @doc ~s(Localized weekday name for a `Fulfillment.Weekday`, e.g. "Friday" / "fredag".)
  @spec weekday_name(Edenflowers.Fulfillment.Weekday.t(), Localize.Locale.locale_id()) :: String.t()
  def weekday_name(weekday, locale) do
    # 1 January 2024 was a Monday.
    ~D[2024-01-01]
    |> Date.add(Edenflowers.Fulfillment.Weekday.to_integer(weekday) - 1)
    |> Localize.Date.to_string!(locale: locale, format: "cccc")
  end

  @doc """
  Weekday with the full date, for customer-facing prose and receipts:
  "Monday 8.6.2026" / "måndag 8.6.2026" / "maanantaina 8.6.2026". The weekday is
  the part the customer acts on; the year keeps far-off dates unambiguous.

  The Finnish form is essive ("on Monday"), so Finnish translations must not put
  a postposition such as "alkaen" or "asti" after it. Swedish and Finnish
  lowercase weekday names: that's CLDR being right, not a missing capitalization.
  """
  @spec weekday_date(Date.t() | nil, Localize.Locale.locale_id()) :: String.t() | nil
  def weekday_date(nil, _locale), do: nil
  def weekday_date(date, locale), do: Localize.Date.to_string!(date, locale: locale, format: "EEEE d.M.yyyy")

  @spec datetime(DateTime.t(), Localize.Locale.locale_id(), String.t()) :: String.t()
  def datetime(datetime, locale, time_zone \\ Edenflowers.ShopTime.timezone()) do
    shifted = DateTime.shift_zone!(datetime, time_zone)
    "#{date(DateTime.to_date(shifted), locale)} #{time(DateTime.to_time(shifted), locale)}"
  end

  # `fractional_digits: 1` — default rounds 25.5% (Finnish VAT) to "26%".
  @spec percentage(number, Localize.Locale.locale_id()) :: String.t()
  def percentage(rate, locale) do
    Localize.Number.to_string!(rate, locale: locale, format: :percent, fractional_digits: 1)
  end
end
