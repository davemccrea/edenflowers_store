defmodule Edenflowers.Fulfillment.DeliveryCost do
  @moduledoc """
  What a delivery costs Jennie in car costs, for comparing with the fee in
  admin. Never charged. Counts the drive back, so twice the distance to the
  address, and leaves out her time.

  Two estimates, each nil until its settings are filled in:

    * `mileage/2` at the kilometrikorvaus, Vero's figure for a car's full
      running costs. A cautious upper estimate.
    * `fuel/2` at the petrol price and the car's consumption. Fuel only, the
      least each extra km costs.
  """

  alias Edenflowers.Fulfillment.FulfillmentOption

  @spec mileage(FulfillmentOption.t(), non_neg_integer()) :: Decimal.t() | nil
  def mileage(%FulfillmentOption{mileage_rate: nil}, _distance), do: nil

  def mileage(%FulfillmentOption{mileage_rate: rate}, distance) do
    distance |> round_trip_km() |> Decimal.mult(rate) |> Decimal.round(2)
  end

  @spec fuel(FulfillmentOption.t(), non_neg_integer()) :: Decimal.t() | nil
  def fuel(%FulfillmentOption{fuel_price: price, fuel_consumption: per_100_km}, _distance)
      when is_nil(price) or is_nil(per_100_km),
      do: nil

  def fuel(%FulfillmentOption{fuel_price: price, fuel_consumption: per_100_km}, distance) do
    distance
    |> round_trip_km()
    |> Decimal.mult(per_100_km)
    |> Decimal.div(100)
    |> Decimal.mult(price)
    |> Decimal.round(2)
  end

  defp round_trip_km(distance), do: Decimal.div(distance * 2, 1000)
end
