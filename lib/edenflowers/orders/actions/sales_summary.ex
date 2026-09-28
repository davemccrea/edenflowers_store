defmodule Edenflowers.Orders.Actions.SalesSummary do
  use Ash.Resource.Actions.Implementation

  require Ash.Query

  @impl true
  def run(input, _opts, context) do
    from = helsinki_midnight_utc(input.arguments.from)
    until = helsinki_midnight_utc(Date.add(input.arguments.to, 1))

    input.resource
    |> Ash.Query.filter(state == :placed and payment_status == :paid and ordered_at >= ^from and ordered_at < ^until)
    |> Ash.aggregate(
      [{:order_count, :count}, {:revenue, :sum, field: :amount_paid, default: Decimal.new("0.00")}],
      Ash.Context.to_opts(context)
    )
  end

  defp helsinki_midnight_utc(date) do
    date
    |> DateTime.new!(~T[00:00:00], "Europe/Helsinki")
    |> DateTime.shift_zone!("Etc/UTC")
  end
end
