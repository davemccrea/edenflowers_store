defmodule Edenflowers.Minimossen.Actions.RecentWeeks do
  @moduledoc """
  Totals Minimossen's weekly sales by Winpos product group for the last `count` weeks
  up to the latest week imported, so the Overview always ends on the newest report
  even before Monday comes round. Averages the 8 weeks before it as the usual week to
  compare with, and totals the year so far.
  """
  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias Edenflowers.Minimossen.WeeklySales

  @average_weeks 8

  @impl true
  def run(input, _opts, context) do
    opts = Ash.Context.to_opts(context)

    case WeeklySales |> Ash.Query.sort(week_start: :desc) |> Ash.Query.limit(1) |> Ash.read_one(opts) do
      {:ok, nil} -> {:ok, %{groups: [], weeks: [], average: nil, year: nil}}
      {:ok, latest} -> summary(latest.week_start, input.arguments.count, opts)
      {:error, error} -> {:error, error}
    end
  end

  defp summary(last, count, opts) do
    first = Date.add(last, -7 * max(count - 1, @average_weeks))

    with {:ok, sales} <- WeeklySales |> Ash.Query.filter(week_start >= ^first) |> Ash.read(opts),
         {:ok, year} <- year(last, opts) do
      groups = groups(sales)
      codes = Enum.map(groups, & &1.code)
      by_week = Enum.group_by(sales, & &1.week_start)

      weeks =
        for week_start <- Date.range(first, last, 7), do: week(week_start, Map.get(by_week, week_start, []), codes)

      before_last = Enum.slice(weeks, -(@average_weeks + 1), @average_weeks)

      {:ok,
       %{
         groups: groups,
         weeks: Enum.take(weeks, -count),
         average: average(Enum.filter(before_last, & &1.reported?), codes),
         year: year
       }}
    end
  end

  # The year is the latest week's ISO week-numbering year, so week 1 can start in December.
  # `first_week_start` says where the imported reports begin, for a year that isn't all in.
  defp year(last, opts) do
    {iso_year, _week} = :calendar.iso_week_number(Date.to_erl(last))
    january_4 = Date.new!(iso_year, 1, 4)
    year_start = Date.add(january_4, 1 - Date.day_of_week(january_4))

    with {:ok, sales} <- WeeklySales |> Ash.Query.filter(week_start >= ^year_start) |> Ash.read(opts) do
      {:ok,
       %{
         total: sum(Enum.map(sales, & &1.gross)),
         first_week_start: sales |> Enum.map(& &1.week_start) |> Enum.min(Date)
       }}
    end
  end

  # Sorted by code as a number ("3" before "66"), each named as its latest report names it.
  defp groups(sales) do
    sales
    |> Enum.sort_by(& &1.week_start, Date)
    |> Map.new(&{&1.group_code, &1.group_name})
    |> Enum.map(fn {code, name} -> %{code: code, name: name} end)
    |> Enum.sort_by(&{String.length(&1.code), &1.code})
  end

  defp week(week_start, sales, codes) do
    by_code = Map.new(sales, &{&1.group_code, &1.gross})

    %{
      week_start: week_start,
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
