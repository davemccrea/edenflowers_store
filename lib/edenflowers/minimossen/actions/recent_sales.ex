defmodule Edenflowers.Minimossen.Actions.RecentSales do
  @moduledoc """
  Totals Minimossen's sales by Winpos product group for the last `count` weeks or
  months up to the latest week imported, so the Overview always ends on the newest
  report even before Monday comes round. By week, averages the 8 weeks
  before each week as the usual week to compare it with. Each period also compares
  with the same period a year before.
  """
  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias Edenflowers.Minimossen.WeeklySales

  @average_weeks 8
  # 52 weeks back lands on the same weekday-aligned week, which an ISO week number
  # can't promise across a 53-week year.
  @year_of_weeks 364

  @impl true
  def run(input, _opts, context) do
    opts = Ash.Context.to_opts(context)

    case WeeklySales |> Ash.Query.sort(week_start: :desc) |> Ash.Query.limit(1) |> Ash.read_one(opts) do
      {:ok, nil} -> {:ok, %{groups: [], periods: []}}
      {:ok, latest} -> summary(input.arguments, latest.week_start, opts)
      {:error, error} -> {:error, error}
    end
  end

  defp summary(%{period: period, count: count, this_year: this_year}, latest, opts) do
    last_start = period_start(period, latest)

    starts =
      for back <- (count - 1)..0//-1,
          start = Date.shift(last_start, [{period, -back}]),
          not this_year or start.year == last_start.year,
          do: start

    # The first period's year-earlier weeks, which also covers the first week's 8-week average.
    first_week = hd(starts) |> Date.shift(year: -1) |> Date.add(-7)

    with {:ok, sales} <- WeeklySales |> Ash.Query.filter(week_start >= ^first_week) |> Ash.read(opts) do
      groups = groups(sales)
      codes = Enum.map(groups, & &1.code)
      by_period = Enum.group_by(sales, &period_start(period, &1.week_start))
      earliest = sales |> Enum.map(& &1.week_start) |> Enum.min(Date)

      periods =
        starts
        |> Enum.map(fn start ->
          start
          |> totals(Map.get(by_period, start, []), codes)
          |> Map.put(:average, if(period == :week, do: average(usual_weeks(start, by_period, codes), codes)))
          |> Map.put(:last_year, last_year(period, start, sales, latest, codes))
          |> Map.put(:partial?, partial?(period, start, earliest, latest))
        end)
        # Periods before the first report are left out, so the chart starts at the first import.
        |> Enum.drop_while(&Date.before?(elem(weeks(period, &1.start), 1), earliest))

      {:ok, %{groups: groups, periods: periods}}
    end
  end

  # Only the weeks up to a year before the latest import, so a month still
  # under way compares with the same stretch of last year's. Nil without a report then.
  defp last_year(period, start, sales, latest, codes) do
    last_year_start = if period == :week, do: Date.add(start, -@year_of_weeks), else: Date.shift(start, year: -1)
    cutoff = Date.add(latest, -@year_of_weeks)

    weeks =
      Enum.filter(
        sales,
        &(period_start(period, &1.week_start) == last_year_start and not Date.after?(&1.week_start, cutoff))
      )

    if weeks != [] do
      last_year_start
      |> totals(weeks, codes)
      |> Map.put(:partial?, period != :week and start == period_start(period, latest))
    end
  end

  # A month still under way, or one that began before the first import, so its
  # bar can't be read against whole ones. A missed import doesn't make one partial.
  defp partial?(period, start, earliest, latest) do
    {first_week, last_week} = weeks(period, start)
    Date.before?(first_week, earliest) or Date.after?(last_week, latest)
  end

  # The first and last weeks counted in the period.
  defp weeks(period, start) do
    first = Date.beginning_of_week(start)
    first = if period_start(period, first) == start, do: first, else: Date.add(first, 7)
    last = start |> Date.shift([{period, 1}]) |> Date.beginning_of_week()
    last = if period_start(period, last) == start, do: last, else: Date.add(last, -7)
    {first, last}
  end

  # A week counts in the month its Thursday falls in, as ISO weeks do.
  defp period_start(:week, week_start), do: week_start
  defp period_start(:month, week_start), do: week_start |> Date.add(3) |> Date.beginning_of_month()

  # Sorted by code as a number ("3" before "66"), each named as its latest report names it.
  # A week without sales only has the code as its name, so a real name wins over it.
  defp groups(sales) do
    sales
    |> Enum.sort_by(&{&1.group_name != &1.group_code, Date.to_gregorian_days(&1.week_start)})
    |> Map.new(&{&1.group_code, &1.group_name})
    |> Enum.map(fn {code, name} -> %{code: code, name: name} end)
    |> Enum.sort_by(&{String.length(&1.code), &1.code})
  end

  defp totals(start, sales, codes) do
    by_code = sales |> Enum.group_by(& &1.group_code, & &1.gross) |> Map.new(fn {code, gross} -> {code, sum(gross)} end)

    %{
      start: start,
      groups: Map.new(codes, &{&1, Map.get(by_code, &1, Decimal.new(0))}),
      total: sum(Map.values(by_code))
    }
  end

  # A week without a report is left out, so a missed import doesn't pull the usual week down.
  defp usual_weeks(week_start, by_week, codes) do
    for before <- @average_weeks..1//-1,
        week = Date.add(week_start, -7 * before),
        sales = Map.get(by_week, week, []),
        sales != [],
        do: totals(week, sales, codes)
  end

  defp average([], _codes), do: nil

  defp average(weeks, codes) do
    mean = fn amounts -> amounts |> sum() |> Decimal.div(length(weeks)) |> Decimal.round(2) end

    %{
      total: mean.(Enum.map(weeks, & &1.total)),
      groups: Map.new(codes, fn code -> {code, mean.(Enum.map(weeks, & &1.groups[code]))} end)
    }
  end

  defp sum(amounts), do: Enum.reduce(amounts, Decimal.new(0), &Decimal.add/2)
end
