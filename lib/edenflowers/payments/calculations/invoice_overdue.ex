defmodule Edenflowers.Payments.Calculations.InvoiceOverdue do
  @moduledoc """
  Whether it is late: still open after its due date, counted in Helsinki days,
  so it turns overdue the day after the due date. A paid or cancelled invoice is
  never overdue; one paid only in part still is.

  Computed in Elixir from the loaded status so the SQL doesn't repeat the
  status CASE.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:status]

  @impl true
  def calculate(records, _opts, _context) do
    today = Edenflowers.ShopTime.today()

    Enum.map(records, fn record ->
      record.status == :open and not is_nil(record.due_date) and
        Date.compare(record.due_date, today) == :lt
    end)
  end
end
