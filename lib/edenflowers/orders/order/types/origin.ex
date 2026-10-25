defmodule Edenflowers.Orders.Order.Types.Origin do
  @moduledoc """
  An online order comes through checkout; a custom order is entered by Jennie
  in the admin; a subscription order is an Occurrence a Subscription created.
  """
  use Ash.Type.Enum, values: [:online, :custom, :subscription]
end
