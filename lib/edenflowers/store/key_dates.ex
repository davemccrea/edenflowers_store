defmodule Edenflowers.Store.KeyDates do
  @moduledoc """
  Florist-relevant key dates rendered as decorations in the checkout calendar.

  The list is intentionally code-defined rather than DB-backed: these holidays
  are stable for years at a time, and version-controlling the list keeps every
  change reviewable. Per-customer reminder dates (the wider auto-send feature)
  will live in a separate, customer-scoped resource.
  """

  @weekdays %{monday: 1, tuesday: 2, wednesday: 3, thursday: 4, friday: 5, saturday: 6, sunday: 7}

  @holidays [
    %{name: "Valentine's Day", icon: "hero-heart-solid", rule: {:fixed, 2, 14}},
    %{name: "Women's Day", icon: "hero-sparkles-solid", rule: {:fixed, 3, 8}},
    %{name: "Mother's Day", icon: "hero-heart-solid", rule: {:nth_weekday, 5, :sunday, 2}},
    %{name: "Father's Day", icon: "hero-heart-solid", rule: {:nth_weekday, 11, :sunday, 2}},
    %{name: "Christmas Eve", icon: "hero-gift-solid", rule: {:fixed, 12, 24}}
  ]

  @spec for_year(integer()) :: [%{date: Date.t(), icon: String.t(), name: String.t()}]
  def for_year(year) do
    Enum.map(@holidays, fn %{rule: rule} = holiday ->
      holiday
      |> Map.delete(:rule)
      |> Map.put(:date, materialise(rule, year))
    end)
  end

  @spec icons_by_date(integer()) :: %{Date.t() => String.t()}
  def icons_by_date(year) do
    year
    |> for_year()
    |> Map.new(fn %{date: date, icon: icon} -> {date, icon} end)
  end

  defp materialise({:fixed, month, day}, year), do: Date.new!(year, month, day)

  defp materialise({:nth_weekday, month, weekday, n}, year) do
    target = Map.fetch!(@weekdays, weekday)
    first = Date.new!(year, month, 1)
    offset = Integer.mod(target - Date.day_of_week(first), 7)
    Date.add(first, offset + (n - 1) * 7)
  end
end
