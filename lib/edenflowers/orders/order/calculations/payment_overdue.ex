defmodule Edenflowers.Orders.Order.Calculations.PaymentOverdue do
  @moduledoc """
  Whether a fulfilled order still has a balance more than 14 days after
  fulfillment.

  Computed in Elixir from the loaded Balance so the SQL doesn't repeat the
  Balance chain for every order in the Overview's unpaid list.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:balance]

  @impl true
  def calculate(records, _opts, _context) do
    overdue_before =
      Date.add(Edenflowers.ShopTime.today(), -Edenflowers.Payments.Payment.overdue_after_days())

    Enum.map(records, fn record ->
      record.fulfillment_status == :fulfilled and Decimal.positive?(record.balance) and
        not is_nil(record.fulfillment_date) and
        Date.compare(record.fulfillment_date, overdue_before) == :lt
    end)
  end
end
