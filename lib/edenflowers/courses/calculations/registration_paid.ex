defmodule Edenflowers.Courses.Calculations.RegistrationPaid do
  @moduledoc """
  Whether a confirmed booking has nothing left to pay and wasn't refunded, for
  its Payment Link page.

  Computed in Elixir from the loaded Balance so the SQL doesn't repeat the
  Balance chain.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:refunded?, :balance]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      record.status == :confirmed and not record.refunded? and Decimal.lte?(record.balance, 0)
    end)
  end
end
