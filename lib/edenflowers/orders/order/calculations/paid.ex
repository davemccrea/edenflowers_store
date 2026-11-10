defmodule Edenflowers.Orders.Order.Calculations.Paid do
  @moduledoc """
  Whether it is paid: committed, its payment status is paid, and it wasn't
  cancelled.

  Computed in Elixir from the loaded payment status so the SQL doesn't repeat the
  payment status CASE.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:committed?, :payment_status, :cancelled?]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, &(&1.committed? and &1.payment_status == :paid and not &1.cancelled?))
  end
end
