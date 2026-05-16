defmodule Edenflowers.Store.KeyDates do
  @moduledoc """
  Florist-relevant key dates rendered as decorations in both the customer
  checkout calendar and the admin fulfillment calendar.

  The list is intentionally code-defined rather than DB-backed: these dates
  are stable for years at a time, and version-controlling the list keeps every
  change reviewable. Per-customer reminder dates (the wider auto-send feature)
  will live in a separate, customer-scoped resource.
  """

  @typedoc "A florist key date materialised for a specific year — the shape returned by `for_year/1`."
  @type key_date :: %{date: Date.t(), name: String.t(), icon: String.t(), colour_class: String.t()}

  @weekdays %{monday: 1, tuesday: 2, wednesday: 3, thursday: 4, friday: 5, saturday: 6, sunday: 7}

  # `colour_class` is the Tailwind text colour applied to the heart in the
  # calendar watermark. Each date gets its own colour so the four key dates
  # remain distinguishable when only the heart shape is shared.
  # Valentine's Day reads as "Friend's Day" (Ystävänpäivä) in Finland — hence
  # the friendly green rather than the romantic red.
  @key_dates [
    %{name: "Valentine's Day", icon: "hero-heart", colour_class: "text-emerald-500", rule: {:fixed, 2, 14}},
    %{name: "Women's Day", icon: "hero-heart", colour_class: "text-violet-500", rule: {:fixed, 3, 8}},
    %{name: "Mother's Day", icon: "hero-heart", colour_class: "text-rose-500", rule: {:nth_weekday, 5, :sunday, 2}},
    %{name: "Father's Day", icon: "hero-heart", colour_class: "text-sky-500", rule: {:nth_weekday, 11, :sunday, 2}}
  ]

  @spec for_year(integer()) :: [key_date()]
  def for_year(year) do
    Enum.map(@key_dates, fn %{rule: rule} = key_date ->
      key_date
      |> Map.delete(:rule)
      |> Map.put(:date, materialise(rule, year))
    end)
  end

  @spec icon_for(Date.t()) :: String.t() | nil
  def icon_for(%Date{} = date) do
    Enum.find_value(@key_dates, fn %{rule: rule, icon: icon} ->
      if materialise(rule, date.year) == date, do: icon
    end)
  end

  @spec colour_class_for(Date.t()) :: String.t() | nil
  def colour_class_for(%Date{} = date) do
    Enum.find_value(@key_dates, fn %{rule: rule, colour_class: colour_class} ->
      if materialise(rule, date.year) == date, do: colour_class
    end)
  end

  defp materialise({:fixed, month, day}, year), do: Date.new!(year, month, day)

  defp materialise({:nth_weekday, month, weekday, n}, year) do
    target = Map.fetch!(@weekdays, weekday)
    first = Date.new!(year, month, 1)
    offset = Integer.mod(target - Date.day_of_week(first), 7)
    Date.add(first, offset + (n - 1) * 7)
  end
end
