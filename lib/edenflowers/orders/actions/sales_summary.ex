defmodule Edenflowers.Orders.Actions.SalesSummary do
  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias Edenflowers.Orders.Payment

  @impl true
  def run(input, _opts, context) do
    from = helsinki_midnight_utc(input.arguments.from)
    until = helsinki_midnight_utc(Date.add(input.arguments.to, 1))

    opts = Ash.Context.to_opts(context)

    {:ok, %{order_count: order_count}} =
      input.resource
      # Any money taken counts the order, so one edited to owe more still counts.
      |> Ash.Query.filter(
        state == :placed and payment_status != :refunded and exists(payments, amount > 0) and
          ordered_at >= ^from and ordered_at < ^until
      )
      |> Ash.aggregate([{:order_count, :count}], opts)

    # Revenue is money received in the range, so a balance paid later counts
    # when it arrives, and a refund when it goes out.
    {:ok, %{revenue: revenue}} =
      Payment
      |> Ash.Query.filter(paid_at >= ^from and paid_at < ^until)
      |> Ash.aggregate([{:revenue, :sum, field: :amount, default: Decimal.new("0.00")}], opts)

    {:ok, %{order_count: order_count, revenue: revenue}}
  end

  defp helsinki_midnight_utc(date) do
    date
    |> DateTime.new!(~T[00:00:00], "Europe/Helsinki")
    |> DateTime.shift_zone!("Etc/UTC")
  end
end
