defmodule Edenflowers.Orders.Order.Types.FulfillmentStatus do
  @moduledoc "The to-make, ready, fulfilled, and cancelled fulfillment states of an order."

  use Ash.Type.Enum, values: [:pending, :ready, :fulfilled, :cancelled]
end
