defmodule Edenflowers.Payments.Calculations.InvoicePaid do
  @moduledoc """
  Whether its Payments cover its amount.

  Computed in Elixir from the loaded status so the SQL doesn't repeat the
  status CASE.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:status]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, &(&1.status == :paid))
  end
end
