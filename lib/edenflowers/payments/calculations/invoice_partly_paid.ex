defmodule Edenflowers.Payments.Calculations.InvoicePartlyPaid do
  @moduledoc """
  Whether it is open with some of its amount already paid, so what is left
  differs from its total.

  Computed in Elixir from the loaded status and payments so the SQL doesn't
  repeat the status CASE and the paid total.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:status, :amount_paid]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, &(&1.status == :open and Decimal.positive?(&1.amount_paid)))
  end
end
