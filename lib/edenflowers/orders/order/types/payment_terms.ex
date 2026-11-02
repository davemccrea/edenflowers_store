defmodule Edenflowers.Orders.Order.Types.PaymentTerms do
  @moduledoc """
  How a custom order's customer will pay, as Jennie chose when placing it:
  through a payment link, by bank transfer, or in person
  on delivery or pickup. The order details email tells the customer.
  The :invoice value is retained for historical bank-transfer terms.
  """
  use Ash.Type.Enum, values: [:payment_link, :invoice, :on_fulfillment]
end
