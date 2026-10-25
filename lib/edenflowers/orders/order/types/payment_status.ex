defmodule Edenflowers.Orders.Order.Types.PaymentStatus do
  @moduledoc """
  The pending, paid, and refunded payment states of an order.
  """

  use Ash.Type.Enum, values: [:pending, :paid, :refunded]
end
