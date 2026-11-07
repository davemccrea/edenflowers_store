defmodule Edenflowers.Orders.Subscription.Calculations.PricePerOrder do
  @moduledoc """
  What each Occurrence costs before any Gift voucher: the variant's current
  price plus the fee `PriceFulfillment` would quote it now, from the option's
  current rates and the first order's distance (the address never changes).
  A free-delivery product pays the free-delivery fee. An address the option no
  longer reaches prices the fee as nothing, since no Occurrence can be made.
  With `fee_only?: true` it is just that fee, so a size picker can price each
  size per delivery.
  """
  use Ash.Resource.Calculation

  alias Edenflowers.Fulfillment.Fee
  alias Edenflowers.Orders.Subscription

  @impl true
  def load(_query, _opts, _context),
    do: [
      :first_order_distance,
      fulfillment_option: [:fulfillment_method, :rate_type, :base_price, :price_per_km, :free_dist_km, :max_dist_km],
      product_variant: [:price, product: [:free_delivery]]
    ]

  @impl true
  def calculate(subscriptions, opts, _context) do
    Enum.map(subscriptions, fn subscription ->
      if opts[:fee_only?],
        do: fee(subscription) || Decimal.new(0),
        else: Subscription.price_per_order(subscription.product_variant.price, fee(subscription))
    end)
  end

  defp fee(%{fulfillment_option: %{fulfillment_method: :pickup} = option}),
    do: Fee.calculate(option, 0).fulfillment_fee

  defp fee(%{first_order_distance: nil}), do: nil

  defp fee(subscription) do
    fees = Fee.calculate(subscription.fulfillment_option, subscription.first_order_distance)

    if subscription.product_variant.product.free_delivery,
      do: fees.free_delivery_fee,
      else: fees.fulfillment_fee
  end
end
