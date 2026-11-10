defmodule Edenflowers.Orders.Order.Calculations.Unpaid do
  @moduledoc """
  Money still owed on a placed order. A fulfilled order can still be unpaid when
  the customer pays afterwards, and an Occurrence whose card was refused is
  placed unpaid.

  Computed in Elixir from the loaded Balance so the SQL doesn't inline the
  Balance chain.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:balance, :refunded?]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      record.state == :placed and Decimal.positive?(record.balance) and not record.refunded?
    end)
  end
end
