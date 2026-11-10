defmodule Edenflowers.Payments.Calculations.InvoiceCancellable do
  @moduledoc """
  Whether Jennie can cancel it with a Credit note: open with nothing paid on it.
  One with Payments, even part-paid, can't be, as those Payments would count
  against no open invoice.

  Computed in Elixir from the loaded status and payments so the SQL doesn't
  repeat the status CASE and the paid total.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:status, :amount_paid]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, &(&1.status == :open and Decimal.equal?(&1.amount_paid, 0)))
  end
end
