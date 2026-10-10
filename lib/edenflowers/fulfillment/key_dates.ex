defmodule Edenflowers.Fulfillment.KeyDates do
  @moduledoc """
  Florist-relevant key dates rendered as decorations in both the customer
  checkout calendar and the admin fulfillment calendar.

  The list is intentionally code-defined rather than DB-backed: these dates
  are stable for years at a time, and version-controlling the list keeps every
  change reviewable. Per-customer reminder dates (the wider auto-send feature)
  will live in a separate, customer-scoped resource.
  """

  alias Edenflowers.Fulfillment.Weekday

  @typedoc "A florist key date materialised for a specific year — the shape returned by `for_year/1`."
  @type key_date :: %{date: Date.t(), key: atom()}

  # Presentation (labels, artwork) lives in `EdenflowersWeb.KeyDateIcon`.
  @key_dates [
    %{key: :valentines_day, rule: {:fixed, 2, 14}},
    %{key: :womens_day, rule: {:fixed, 3, 8}},
    %{key: :mothers_day, rule: {:nth_weekday, 5, :sunday, 2}},
    %{key: :fathers_day, rule: {:nth_weekday, 11, :sunday, 2}}
  ]

  @spec for_year(integer()) :: [key_date()]
  def for_year(year) do
    Enum.map(@key_dates, fn %{key: key, rule: rule} -> %{key: key, date: materialise(rule, year)} end)
  end

  @doc "Key dates falling in the same month as `date`, in date order."
  @spec for_month(Date.t()) :: [key_date()]
  def for_month(%Date{year: year, month: month}) do
    year
    |> for_year()
    |> Enum.filter(&(&1.date.month == month))
    |> Enum.sort_by(& &1.date, Date)
  end

  @doc "The key for `date`, or `nil` when it isn't a key date."
  @spec lookup_for(Date.t()) :: atom() | nil
  def lookup_for(%Date{} = date) do
    Enum.find_value(@key_dates, fn %{key: key, rule: rule} ->
      if materialise(rule, date.year) == date, do: key
    end)
  end

  @doc "Whether `date` is one of the florist key dates."
  @spec key_date?(Date.t()) :: boolean()
  def key_date?(%Date{} = date), do: lookup_for(date) != nil

  @doc """
  Key dates falling on `weekday` for the current and following year. The
  two-year lookahead matches the calendar's visible horizon.
  """
  @spec dates_for_weekday(Weekday.t()) :: [Date.t()]
  def dates_for_weekday(weekday) do
    year = Date.utc_today().year

    [year, year + 1]
    |> Enum.flat_map(&for_year/1)
    |> Enum.map(& &1.date)
    |> Enum.filter(&(Weekday.from_date(&1) == weekday))
  end

  defp materialise({:fixed, month, day}, year), do: Date.new!(year, month, day)

  defp materialise({:nth_weekday, month, weekday, n}, year) do
    target = Weekday.to_integer(weekday)
    first = Date.new!(year, month, 1)
    offset = Integer.mod(target - Date.day_of_week(first), 7)
    Date.add(first, offset + (n - 1) * 7)
  end
end
