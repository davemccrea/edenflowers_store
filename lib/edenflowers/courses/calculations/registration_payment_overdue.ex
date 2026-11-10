defmodule Edenflowers.Courses.Calculations.RegistrationPaymentOverdue do
  @moduledoc """
  Whether a booking still has a balance more than 14 days after the course.

  Computed in Elixir from the loaded Balance and course so the SQL doesn't repeat
  the Balance chain for every booking in the Overview's unpaid list.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:balance, :course]

  @impl true
  def calculate(records, _opts, _context) do
    overdue_before =
      Date.add(Edenflowers.ShopTime.today(), -Edenflowers.Payments.Payment.overdue_after_days())

    Enum.map(records, fn record ->
      Decimal.positive?(record.balance) and Date.compare(record.course.date, overdue_before) == :lt
    end)
  end
end
