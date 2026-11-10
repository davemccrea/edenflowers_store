defmodule Edenflowers.Payments.Calculations.InvoiceOpen do
  @moduledoc """
  Whether the invoice is open: issued, neither covered by a Credit note nor paid
  in full. Only an open invoice can take a Payment or be emailed.

  Computed in Elixir from the loaded status so the SQL doesn't repeat the whole
  status CASE (which sums its Payments and looks for a Credit note) for every
  open/payable/sendable question.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:status]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, &(&1.status == :open))
  end
end
