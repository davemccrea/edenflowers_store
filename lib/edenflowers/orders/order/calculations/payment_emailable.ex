defmodule Edenflowers.Orders.Order.Calculations.PaymentEmailable do
  @moduledoc """
  Whether a payment on the order can be emailed. A Gift voucher sale's only once
  it's paid in full, since the email carries the voucher, so a part payment in
  cash beside one by card waits for the rest.

  Computed in Elixir from the loaded values so the SQL doesn't repeat the
  receipt and Balance chains.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:receipt_available?, :cancelled?, :gift_voucher_sale?]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      not record.gift_voucher_sale? or (record.receipt_available? and not record.cancelled?)
    end)
  end
end
