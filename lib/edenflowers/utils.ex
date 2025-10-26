defmodule Edenflowers.Utils do
  @moduledoc """
  Common utility functions for the Edenflowers application.
  """

  def format_money(nil), do: format_money(0)

  def format_money(value) do
    Cldr.Number.to_string!(value,
      format: :currency,
      currency: "EUR",
      locale: Cldr.get_locale()
    )
  end

  def format_date(nil), do: ""

  def format_date(date) do
    case Cldr.Date.to_string(date, Edenflowers.Cldr, locale: Cldr.get_locale(), format: :medium) do
      {:ok, formatted} -> formatted
      _ -> ""
    end
  end

  def format_datetime(nil), do: ""

  def format_datetime(datetime) do
    with {:ok, date_part} <-
           Cldr.Date.to_string(datetime, Edenflowers.Cldr, locale: Cldr.get_locale(), format: :short),
         {:ok, time_part} <-
           Cldr.Time.to_string(datetime, Edenflowers.Cldr, locale: Cldr.get_locale(), format: :short) do
      "#{date_part} #{time_part}"
    else
      _ -> ""
    end
  end
end
