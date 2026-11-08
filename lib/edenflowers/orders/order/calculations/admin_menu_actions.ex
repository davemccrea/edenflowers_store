defmodule Edenflowers.Orders.Order.Calculations.AdminMenuActions do
  @moduledoc "The selectable order-menu actions, derived from the order's action eligibility."

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context) do
    [
      :receipt_available?,
      :customer_email,
      :gift_voucher_sale?,
      :cancelled?,
      :details_emailable?,
      :payment_reminder_sendable?,
      :fulfillment_confirmation_sendable?,
      :refundable?,
      :pass_it_on_card_removable?,
      :cancellable?,
      :invoiced?
    ]
  end

  @impl true
  def calculate(orders, _opts, _context) do
    Enum.map(orders, fn order ->
      receipt_emailable? = order.receipt_available? && !is_nil(order.customer_email)

      for {action, available?} <- [
            {:gift_voucher, receipt_emailable? && order.gift_voucher_sale? && !order.cancelled?},
            {:receipt, receipt_emailable? && !order.gift_voucher_sale?},
            {:order_details, !order.receipt_available? && order.details_emailable?},
            {:payment_reminder, order.payment_reminder_sendable?},
            {:fulfillment, order.fulfillment_confirmation_sendable?},
            {:view_receipt, order.receipt_available?},
            {:refund, order.refundable?},
            {:unlink_card, order.pass_it_on_card_removable?},
            {:cancel, order.cancellable? && !order.invoiced?}
          ],
          available?,
          do: action
    end)
  end
end
