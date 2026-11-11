defmodule Edenflowers.Fulfillment.KeyDates do
  @moduledoc """
  Florist key dates calculated from fixed dates, weekday rules and Easter,
  shared by the checkout and admin calendars. Labels and artwork live in
  `EdenflowersWeb.KeyDateIcon`.
  """

  alias Edenflowers.Fulfillment.Weekday

  # Presentation (labels, artwork) lives in `EdenflowersWeb.KeyDateIcon`.
  @key_dates [
    %{key: :valentines_day, rule: {:fixed, 2, 14}},
    %{key: :womens_day, rule: {:fixed, 3, 8}},
    %{key: :easter, rule: :easter},
    %{key: :mothers_day, rule: {:nth_weekday, 5, :sunday, 2}},
    %{key: :fathers_day, rule: {:nth_weekday, 11, :sunday, 2}},
    # A one-off date has no rule to repeat it, so add each year's date and
    # remove the past ones.
    %{key: :examenshelg, rule: {:one_off, ~D[2027-05-28]}}
  ]

  @typedoc "A florist key date materialised for a specific year — the shape returned by `for_year/1`."
  @type key_date :: %{date: Date.t(), key: atom()}

  @spec for_year(integer()) :: [key_date()]
  def for_year(year) do
    @key_dates
    |> Enum.map(fn %{key: key, rule: rule} -> %{key: key, date: materialise(rule, year)} end)
    |> Enum.reject(&is_nil(&1.date))
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
    date.year
    |> for_year()
    |> Enum.find_value(fn %{key: key, date: known} -> if known == date, do: key end)
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
    year = Edenflowers.ShopTime.today().year

    [year, year + 1]
    |> Enum.flat_map(&for_year/1)
    |> Enum.map(& &1.date)
    |> Enum.filter(&(Weekday.from_date(&1) == weekday))
  end

  defp materialise({:fixed, month, day}, year), do: Date.new!(year, month, day)

  # Easter Sunday is a moving feast; the anonymous Gregorian computus
  # (Meeus/Jones/Butcher) turns the year into its date.
  defp materialise(:easter, year) do
    a = rem(year, 19)
    b = div(year, 100)
    c = rem(year, 100)
    d = div(b, 4)
    e = rem(b, 4)
    f = div(b + 8, 25)
    g = div(b - f + 1, 3)
    h = rem(19 * a + b - d - g + 15, 30)
    i = div(c, 4)
    k = rem(c, 4)
    l = rem(32 + 2 * e + 2 * i - h - k, 7)
    m = div(a + 11 * h + 22 * l, 451)
    month = div(h + l - 7 * m + 114, 31)
    day = rem(h + l - 7 * m + 114, 31) + 1

    Date.new!(year, month, day)
  end

  defp materialise({:one_off, %Date{year: one_off_year} = date}, year) when one_off_year == year, do: date
  defp materialise({:one_off, %Date{}}, _year), do: nil

  defp materialise({:nth_weekday, month, weekday, n}, year) do
    target = Weekday.to_integer(weekday)
    first = Date.new!(year, month, 1)
    offset = Integer.mod(target - Date.day_of_week(first), 7)
    Date.add(first, offset + (n - 1) * 7)
  end
end
