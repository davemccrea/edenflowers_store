defmodule Edenflowers.Orders.Order.CheckoutPrice do
  @moduledoc """
  What checkout's summary shows a cart costing. Until the delivery step is
  submitted the cart has no fee, so it's priced from the address quoted so far,
  by the same rule `submit_delivery` stores. After that the cart's own fee is
  what Stripe charges.

  Needs `items_total`, `free_delivery?`, `fulfillment_fee`, `fulfillment_option`
  and what `Calculations.Vat` loads.
  """

  alias Edenflowers.Fulfillment.Fee
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Calculations.Vat

  @doc "`fee` is nil until there's one to show. `distance` is the quoted address's, in metres, or nil."
  def price(order, distance) do
    fee = fee(order, distance)
    %{fee: fee, total: Decimal.add(order.items_total, fee || 0), vat: Vat.total(%{order | fulfillment_fee: fee})}
  end

  defp fee(%{state: :delivery, fulfillment_method: :pickup, fulfillment_option: %{} = option}, _distance),
    do: Fee.calculate(option, 0).fulfillment_fee

  defp fee(%{state: :delivery, fulfillment_option: %{} = option} = order, distance) when is_integer(distance) do
    quoted = Fee.calculate(option, distance)
    Orders.charged_fulfillment_fee!(quoted.fulfillment_fee, quoted.free_delivery_fee, order.free_delivery?)
  end

  defp fee(%{state: :delivery}, _distance), do: nil
  defp fee(order, _distance), do: order.fulfillment_fee
end
