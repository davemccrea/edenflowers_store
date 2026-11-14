defmodule Edenflowers.Minimossen.Actions.RecentSales do
  @moduledoc """
  Totals Minimossen's sales by Winpos product group for the last `count` weeks, months
  or years up to the latest week imported, so the Overview always ends on the newest
  report even before Monday comes round. By week, averages the 8 weeks before each
  week as the usual week to compare it with.
  """
  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias Edenflowers.Minimossen.WeeklySales

  @average_weeks 8

  @impl true
  def run(input, _opts, context) do
    opts = Ash.Context.to_opts(context)

    case WeeklySales |> Ash.Query.sort(week_start: :desc) |> Ash.Query.limit(1) |> Ash.read_one(opts) do
      {:ok, nil} -> {:ok, %{groups: [], periods: []}}
      {:ok, latest} -> summary(input.arguments.period, latest.week_start, input.arguments.count, opts)
      {:error, error} -> {:error, error}
    end
  end

  defp summary(period, last, count, opts) do
    last_start = period_start(period, last)
    starts = for back <- (count - 1)..0//-1, do: Date.shift(last_start, [{period, -back}])
    # A week whose Thursday is in the first period starts up to 3 days before it,
    # and the first week's average needs the 8 weeks before it.
    first_week = if period == :week, do: Date.add(hd(starts), -7 * @average_weeks), else: Date.add(hd(starts), -3)

    with {:ok, sales} <- WeeklySales |> Ash.Query.filter(week_start >= ^first_week) |> Ash.read(opts) do
      groups = groups(sales)
      codes = Enum.map(groups, & &1.code)
      by_period = Enum.group_by(sales, &period_start(period, &1.week_start))

      periods =
        starts
        |> Enum.map(fn start ->
          start
          |> totals(Map.get(by_period, start, []), codes)
          |> Map.put(:average, if(period == :week, do: average(usual_weeks(start, by_period, codes), codes)))
        end)
        # Periods before the first report are left out, so the year view starts at the first import.
        |> Enum.drop_while(&(not &1.reported?))

      {:ok, %{groups: groups, periods: periods}}
    end
  end

  # A week counts in the month and ISO year its Thursday falls in, as ISO weeks do.
  defp period_start(:week, week_start), do: week_start
  defp period_start(:month, week_start), do: week_start |> Date.add(3) |> Date.beginning_of_month()
  defp period_start(:year, week_start), do: Date.new!(Date.add(week_start, 3).year, 1, 1)

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
