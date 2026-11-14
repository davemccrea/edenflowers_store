defmodule Edenflowers.Minimossen.Actions.RecentWeeks do
  @moduledoc """
  Totals Minimossen's weekly sales into flowers and shop for the last `count` weeks
  up to the latest week imported, so the Overview always ends on the newest report
  even before Monday comes round. Averages the 8 weeks before it as the usual week to
  compare with, and totals the year so far.
  """
  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias Edenflowers.Minimossen.WeeklySales

  # Winpos product group 3 is Eden Flowers kukat; every other Eden group is the shop.
  @flowers_group "3"
  @average_weeks 8

  @impl true
  def run(input, _opts, context) do
    opts = Ash.Context.to_opts(context)

    case WeeklySales |> Ash.Query.sort(week_start: :desc) |> Ash.Query.limit(1) |> Ash.read_one(opts) do
      {:ok, nil} -> {:ok, %{weeks: [], average: nil, year: nil}}
      {:ok, latest} -> summary(latest.week_start, input.arguments.count, opts)
      {:error, error} -> {:error, error}
    end
  end

  defp summary(last, count, opts) do
    first = Date.add(last, -7 * max(count - 1, @average_weeks))

    with {:ok, sales} <- WeeklySales |> Ash.Query.filter(week_start >= ^first) |> Ash.read(opts),
         {:ok, year} <- year(last, opts) do
      by_week = Enum.group_by(sales, & &1.week_start)
      weeks = for week_start <- Date.range(first, last, 7), do: week(week_start, Map.get(by_week, week_start, []))
      before_last = Enum.slice(weeks, -(@average_weeks + 1), @average_weeks)

      {:ok, %{weeks: Enum.take(weeks, -count), average: average(Enum.filter(before_last, & &1.reported?)), year: year}}
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

  defp week(week_start, sales) do
    {flowers, shop} = Enum.split_with(sales, &(&1.group_code == @flowers_group))
    flowers = sum(Enum.map(flowers, & &1.gross))
    shop = sum(Enum.map(shop, & &1.gross))

    %{week_start: week_start, flowers: flowers, shop: shop, total: Decimal.add(flowers, shop), reported?: sales != []}
  end

  # A week without a report is left out, so a missed import doesn't pull the usual week down.
  defp average([]), do: nil

  defp average(weeks) do
    Map.new([:flowers, :shop, :total], fn key ->
      {key, weeks |> Enum.map(&Map.fetch!(&1, key)) |> sum() |> Decimal.div(length(weeks)) |> Decimal.round(2)}
    end)
  end

  defp sum(amounts), do: Enum.reduce(amounts, Decimal.new(0), &Decimal.add/2)
end
