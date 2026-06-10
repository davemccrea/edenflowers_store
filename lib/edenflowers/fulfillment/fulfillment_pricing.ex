defmodule Edenflowers.Fulfillment.FulfillmentPricing do
  @moduledoc """
  Pure fulfillment-fee calculation. Shared by the `calculate_price` action
  (which loads the option first) and `calculate_delivery` (which already holds
  the loaded option after geocoding), the same split as
  `FulfillmentCalendar.unavailable_reason/3` vs the `fulfill_on_date` action.
  """

  alias Edenflowers.Fulfillment.FulfillmentOption

  @typedoc """
  The fee for a distance, or `:out_of_delivery_range` when it's beyond the
  option's `max_dist_km`. Out-of-range rides in `:error` rather than being an
  error proper, so callers match the reason instead of an Ash.Error.Unknown.
  """
  @type result ::
          %{error: nil, fulfillment_fee: Decimal.t()}
          | %{error: :out_of_delivery_range, fulfillment_fee: nil}

  @spec price(FulfillmentOption.t(), Decimal.t()) :: result()
  def price(%FulfillmentOption{rate_type: :fixed} = option, _distance) do
    %{error: nil, fulfillment_fee: option.base_price}
  end

  def price(%FulfillmentOption{rate_type: :dynamic} = option, %Decimal{} = distance) do
    %{
      price_per_km: price_per_km,
      base_price: base_price,
      free_dist_km: free_dist_km,
      max_dist_km: max_dist_km
    } = option

    price_per_m = Decimal.div(price_per_km, 1000)
    free_dist_m = Decimal.mult(free_dist_km, 1000)
    max_dist_m = Decimal.mult(max_dist_km, 1000)

    cond do
      Decimal.lte?(distance, free_dist_m) ->
        %{error: nil, fulfillment_fee: Decimal.new("0")}

      Decimal.gt?(distance, free_dist_m) and Decimal.lt?(distance, max_dist_m) ->
        fee =
          distance
          |> Decimal.sub(free_dist_m)
          |> Decimal.mult(price_per_m)
          |> Decimal.add(base_price)
          |> Decimal.round(2)

        %{error: nil, fulfillment_fee: fee}

      true ->
        %{error: :out_of_delivery_range, fulfillment_fee: nil}
    end
  end
end
