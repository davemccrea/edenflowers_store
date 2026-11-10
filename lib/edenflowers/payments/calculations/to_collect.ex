defmodule Edenflowers.Payments.Calculations.ToCollect do
  @moduledoc """
  Whether money is still owed by the customer: a Balance left to collect that
  no refund has already settled.

  Computed from the loaded Balance rather than as an expression, so the SQL
  doesn't carry a second copy of the Balance's own calculation chain.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:balance, :refunded?]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, &(not &1.refunded? and Decimal.positive?(&1.balance)))
  end
end
