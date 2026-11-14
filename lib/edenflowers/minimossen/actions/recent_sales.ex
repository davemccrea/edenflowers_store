defmodule Edenflowers.Minimossen.Actions.RecentSales do
  @moduledoc """
  Totals Minimossen's sales by Winpos product group for the last `count` weeks, months
  or years up to the latest week imported, so the Overview always ends on the newest
  report even before Monday comes round. By week, averages the 8 weeks before the
  latest as the usual week to compare with. Totals the year so far.
  """
  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias Edenflowers.Minimossen.WeeklySales

  @average_weeks 8

  @impl true
  def run(input, _opts, context) do
    opts = Ash.Context.to_opts(context)

    case WeeklySales |> Ash.Query.sort(week_start: :desc) |> Ash.Query.limit(1) |> Ash.read_one(opts) do
      {:ok, nil} -> {:ok, %{groups: [], periods: [], average: nil, year: nil}}
      {:ok, latest} -> summary(input.arguments.period, latest.week_start, input.arguments.count, opts)
      {:error, error} -> {:error, error}
    end
  end

  defp summary(period, last, count, opts) do
    last_start = period_start(period, last)
    starts = for back <- (count - 1)..0//-1, do: Date.shift(last_start, [{period, -back}])
    average_from = Date.add(last, -7 * @average_weeks)
    # A week whose Thursday is in the first period starts up to 3 days before it.
    first_week = Date.add(Enum.min([hd(starts), average_from], Date), -3)

    with {:ok, sales} <- WeeklySales |> Ash.Query.filter(week_start >= ^first_week) |> Ash.read(opts),
         {:ok, year} <- year(last, opts) do
      groups = groups(sales)
      codes = Enum.map(groups, & &1.code)
      by_period = Enum.group_by(sales, &period_start(period, &1.week_start))
      by_week = Enum.group_by(sales, & &1.week_start)

      usual_weeks =
        for week_start <- Date.range(average_from, Date.add(last, -7), 7),
            sales = Map.get(by_week, week_start, []),
            sales != [],
            do: totals(week_start, sales, codes)

      {:ok,
       %{
         groups: groups,
         # Periods before the first report are left out, so the year view starts at the first import.
         periods:
           starts
           |> Enum.map(&totals(&1, Map.get(by_period, &1, []), codes))
           |> Enum.drop_while(&(not &1.reported?)),
         average: if(period == :week, do: average(usual_weeks, codes)),
         year: year
       }}
    end
  end

  # A week counts in the month and ISO year its Thursday falls in, as ISO weeks do.
  defp period_start(:week, week_start), do: week_start
  defp period_start(:month, week_start), do: week_start |> Date.add(3) |> Date.beginning_of_month()
  defp period_start(:year, week_start), do: Date.new!(Date.add(week_start, 3).year, 1, 1)

  # The year is the latest week's ISO week-numbering year, so week 1 can start in December.
  # `first_week_start` says where the imported reports begin, for a year that isn't all in,
  # and `last_week_start` where they end.
  defp year(last, opts) do
    {iso_year, _week} = :calendar.iso_week_number(Date.to_erl(last))
    january_4 = Date.new!(iso_year, 1, 4)
    year_start = Date.add(january_4, 1 - Date.day_of_week(january_4))

    with {:ok, sales} <- WeeklySales |> Ash.Query.filter(week_start >= ^year_start) |> Ash.read(opts) do
      {:ok,
       %{
         total: sum(Enum.map(sales, & &1.gross)),
         first_week_start: sales |> Enum.map(& &1.week_start) |> Enum.min(Date),
         last_week_start: last
       }}
    end
  end

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
      total: sum(Map.values(by_code)),
      reported?: sales != []
    }
  end

  # A week without a report is left out, so a missed import doesn't pull the usual week down.
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
