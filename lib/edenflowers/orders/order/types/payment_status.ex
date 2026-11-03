defmodule Edenflowers.Orders.Order.Types.PaymentStatus do
  @moduledoc """
  The pending, paid, invoiced and refunded payment states of an order.
  """

  use Ash.Type.Enum, values: [:pending, :paid, :invoiced, :refunded]
end
