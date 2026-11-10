defmodule Edenflowers.Orders.Order.Calculations.Invoiceable do
  @moduledoc """
  Whether Jennie can invoice it: a Custom Order on invoice terms with nothing
  paid, a Balance to collect and no invoice already covering it.

  Computed in Elixir from the loaded values so the SQL doesn't repeat the
  Balance chain and the invoices `exists`.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:amount_held, :balance, :invoiced?]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      record.state == :placed and record.origin == :custom and record.payment_terms == :invoice and
        Decimal.equal?(record.amount_held, 0) and Decimal.positive?(record.balance) and
        not record.invoiced?
    end)
  end
end
