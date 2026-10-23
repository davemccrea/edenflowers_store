defmodule Edenflowers.Orders.Actions.SalesSummary do
  @moduledoc """
  Counts placed orders that hold money and totals payment rows received or
  refunded in the interval. Both use Helsinki day boundaries; revenue includes
  payments for course bookings as well as orders.
  """

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias Edenflowers.Payments.Payment

  @impl true
  def run(input, _opts, context) do
    from = helsinki_midnight_utc(input.arguments.from)
    until = helsinki_midnight_utc(Date.add(input.arguments.to, 1))

    opts = Ash.Context.to_opts(context)

    {:ok, %{order_count: order_count}} =
      input.resource
      # Any money taken counts the order, so one edited to owe more still counts.
      |> Ash.Query.filter(
        state == :placed and holds_money? and
          ordered_at >= ^from and ordered_at < ^until
      )
      |> Ash.aggregate([{:order_count, :count}], opts)

    # Revenue is money received in the range, so a balance paid later counts
    # when it arrives, and a refund when it goes out.
    payments =
      Payment
      |> Ash.Query.filter(paid_at >= ^from and paid_at < ^until)
      |> Ash.Query.select([:amount, :paid_at])
      |> Ash.read!(opts)

    by_date =
      Enum.group_by(payments, &Edenflowers.ShopTime.today(&1.paid_at), & &1.amount)

    revenue_by_day =
      for date <- Date.range(input.arguments.from, input.arguments.to) do
        %{date: date, revenue: by_date |> Map.get(date, []) |> sum()}
      end

    {:ok,
     %{
       order_count: order_count,
       revenue: revenue_by_day |> Enum.map(& &1.revenue) |> sum(),
       revenue_by_day: revenue_by_day
     }}
  end

  defp sum(amounts), do: Enum.reduce(amounts, Decimal.new("0.00"), &Decimal.add/2)

  defp helsinki_midnight_utc(date) do
    date
    |> DateTime.new!(~T[00:00:00], Edenflowers.ShopTime.timezone())
    |> DateTime.shift_zone!("Etc/UTC")
  end
end
