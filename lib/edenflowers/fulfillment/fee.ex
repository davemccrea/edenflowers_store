defmodule Edenflowers.Fulfillment.Fee do
  @moduledoc """
  Pure fulfillment-fee calculation, used by the `calculate_delivery` action
  after geocoding and directly for pickup, which has no distance.
  """

  alias Edenflowers.Fulfillment.FulfillmentOption

  @typedoc """
  The fee for a distance, or `:out_of_delivery_range` when it's beyond the
  option's `max_dist_km`. Out-of-range rides in `:error` rather than being an
  error proper, so callers match the reason instead of an Ash.Error.Unknown.

  A distance-priced fee is `base_price` plus `price_per_km` for every km from
  the shop. `free_dist_km` only marks `in_free_delivery_zone`: the order waives
  the fee there when its cart holds a free-delivery product.
  """
  @type result ::
          %{error: nil, fulfillment_fee: Decimal.t(), in_free_delivery_zone: boolean()}
          | %{error: :out_of_delivery_range, fulfillment_fee: nil, in_free_delivery_zone: false}

  @spec calculate(FulfillmentOption.t(), non_neg_integer()) :: result()
  def calculate(%FulfillmentOption{rate_type: :fixed} = option, distance) when is_integer(distance) do
    %{error: nil, fulfillment_fee: option.base_price, in_free_delivery_zone: false}
  end

  def calculate(%FulfillmentOption{rate_type: :dynamic} = option, distance) when is_integer(distance) do
    %{
      price_per_km: price_per_km,
      base_price: base_price,
      free_dist_km: free_dist_km,
      max_dist_km: max_dist_km
    } = option

    distance = Decimal.new(distance)
    price_per_m = Decimal.div(price_per_km, 1000)
    free_dist_m = Decimal.mult(free_dist_km, 1000)
    max_dist_m = Decimal.mult(max_dist_km, 1000)

    if Decimal.lt?(distance, max_dist_m) do
      fee =
        distance
        |> Decimal.mult(price_per_m)
        |> Decimal.add(base_price)
        |> Decimal.round(2)

      %{error: nil, fulfillment_fee: fee, in_free_delivery_zone: Decimal.lte?(distance, free_dist_m)}
    else
      %{error: :out_of_delivery_range, fulfillment_fee: nil, in_free_delivery_zone: false}
    end
  end
end
