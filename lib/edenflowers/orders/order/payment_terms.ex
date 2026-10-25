defmodule Edenflowers.Orders.Order.PaymentTerms do
  @moduledoc """
  How a custom order's customer will pay, as Jennie chose when placing it:
  through a payment link, by an invoice sent after fulfilment, or in person
  on delivery or pickup. The order details email tells the customer.
  """
  use Ash.Type.Enum, values: [:payment_link, :invoice, :on_fulfillment]
end
