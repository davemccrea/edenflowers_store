defmodule Edenflowers.Fulfillment.Fee do
  @moduledoc """
  Pure fulfillment-fee calculation, used by the `calculate_delivery` action
  after geocoding and directly for pickup, which has no distance.
  """

  alias Edenflowers.Fulfillment.FulfillmentOption

  @typedoc """
  The fees for a distance, or `:out_of_delivery_range` when it's beyond the
  option's `max_dist_km`. Out-of-range rides in `:error` rather than being an
  error proper, so callers match the reason instead of an Ash.Error.Unknown.

  `fulfillment_fee` is what any cart pays: for a distance-priced option,
  `base_price` plus `price_per_km` for every km from the shop.
  `free_delivery_fee` is what a cart holding a free-delivery product pays: the
  first `free_dist_km` are free, so nothing up to there, and past it
  `base_price` plus `price_per_km` for every km beyond `free_dist_km`. A
  fixed-rate option has no free distance, so both are its `base_price`.
  """
  @type result ::
          %{error: nil, fulfillment_fee: Decimal.t(), free_delivery_fee: Decimal.t()}
          | %{error: :out_of_delivery_range, fulfillment_fee: nil, free_delivery_fee: nil}

  @spec calculate(FulfillmentOption.t(), non_neg_integer()) :: result()
  def calculate(%FulfillmentOption{rate_type: :fixed} = option, distance) when is_integer(distance) do
    %{error: nil, fulfillment_fee: option.base_price, free_delivery_fee: option.base_price}
  end

  def calculate(%FulfillmentOption{rate_type: :dynamic} = option, distance) when is_integer(distance) do
    %{free_dist_km: free_dist_km, max_dist_km: max_dist_km} = option

    free_dist_m = free_dist_km * 1000

    if distance < max_dist_km * 1000 do
      free_delivery_fee =
        if free_dist_km > 0 and distance <= free_dist_m,
          do: Decimal.new(0),
          else: distance_fee(option, distance - free_dist_m)

      %{error: nil, fulfillment_fee: distance_fee(option, distance), free_delivery_fee: free_delivery_fee}
    else
      %{error: :out_of_delivery_range, fulfillment_fee: nil, free_delivery_fee: nil}
    end
  end

  # base_price plus price_per_km for each of `metres`, to the cent.
  defp distance_fee(option, metres) do
    metres
    |> Decimal.new()
    |> Decimal.mult(option.price_per_km)
    |> Decimal.div(1000)
    |> Decimal.add(option.base_price)
    |> Decimal.round(2)
  end
end
