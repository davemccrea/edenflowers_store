defmodule Edenflowers.Orders.Order.FulfillmentStatus do
  @moduledoc "The pending, fulfilled, and cancelled fulfillment states of an order."

  use Ash.Type.Enum, values: [:pending, :fulfilled, :cancelled]
end
