defmodule Edenflowers.Orders.Order.Calculations.PaymentReminderSendable do
  @moduledoc """
  Whether Jennie can send a Payment reminder: a Balance to collect, an email to
  send it to, on a purchase that has not been cancelled. Never a Gift voucher
  sale, paid at the counter when Jennie sells it or at checkout online.

  Computed in Elixir from the loaded values so the SQL doesn't repeat the
  Balance chain.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:to_collect?, :gift_voucher_sale?]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      record.fulfillment_status != :cancelled and not is_nil(record.customer_email) and
        record.to_collect? and not record.gift_voucher_sale?
    end)
  end
end
