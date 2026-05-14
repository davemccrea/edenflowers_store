defmodule Edenflowers.Localize.Format do
  @moduledoc """
  Locale-aware formatting helpers shared between the order-confirmation
  email body and the PDF receipt payload. All functions return strings
  formatted via CLDR for the supplied locale.
  """

  def currency(amount, locale) do
    Localize.Number.to_string!(amount, locale: locale, currency: :EUR)
  end

  def date(date, locale) do
    Localize.Date.to_string!(date, locale: locale, format: :short)
  end

  def datetime(datetime, locale) do
    {:ok, date_part} = Localize.Date.to_string(datetime, locale: locale, format: :short)
    {:ok, time_part} = Localize.Time.to_string(datetime, locale: locale, format: :short)
    "#{date_part} #{time_part}"
  end

  # Tax rates are stored on LineItem as raw decimals (e.g. 0.255 for 25.5%).
  # CLDR's :percent format multiplies by 100 and appends the locale-correct
  # symbol. The Finnish VAT rate carries a fractional digit (25.5%), so
  # we pin `fractional_digits: 1` — the default rounds to whole percents
  # and would render "26%" for the standard rate.
  def percentage(rate, locale) do
    Localize.Number.to_string!(rate, locale: locale, format: :percent, fractional_digits: 1)
  end
end
