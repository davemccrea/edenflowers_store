defmodule Edenflowers.Payments.Calculations.InvoiceAmountUnpaid do
  @moduledoc """
  What is still to pay on it in euros: its amount less its Payments, which can't
  exceed it.

  Computed in Elixir from the loaded paid total so the SQL doesn't repeat the
  payments aggregate.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:amount_paid]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, &Decimal.sub(&1.amount, &1.amount_paid))
  end
end
