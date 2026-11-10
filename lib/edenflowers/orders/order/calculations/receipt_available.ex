defmodule Edenflowers.Orders.Order.Calculations.ReceiptAvailable do
  @moduledoc """
  Whether the order has a receipt to send: placed and paid.

  Computed from the loaded payment status so the SQL doesn't inline the status
  and Balance chain into every order that asks for a receipt.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:payment_status]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, &(&1.state == :placed and &1.payment_status == :paid))
  end
end
