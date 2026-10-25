defmodule Edenflowers.Orders.Order.Types.CustomerStatus do
  @moduledoc """
  Where an order stands, as its customer reads it beside its date. A past date
  Jennie hasn't marked fulfilled stays scheduled: it never claims a delivery
  the data doesn't support.
  """
  use Ash.Type.Enum,
    values: [
      :refunded,
      :cancelled,
      :confirmed,
      :collected,
      :delivered,
      :ready_today,
      :arriving_today,
      :for_pickup,
      :arriving,
      :pickup_scheduled,
      :delivery_scheduled
    ]
end
