defmodule Edenflowers.Courses.Calculations.RegistrationCancelledUnsettled do
  @moduledoc """
  Whether a cancelled booking still needs Jennie: money to refund, a cancellation
  charge to collect.

  Computed in Elixir from the loaded settlement so the SQL doesn't repeat the
  Balance chain behind `settled?` for every booking on the course page.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:settled?]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, &(&1.status == :cancelled and not &1.settled?))
  end
end
