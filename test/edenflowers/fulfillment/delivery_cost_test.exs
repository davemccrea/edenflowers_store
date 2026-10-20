defmodule Edenflowers.Fulfillment.DeliveryCostTest do
  use ExUnit.Case, async: true

  alias Edenflowers.Fulfillment.DeliveryCost
  alias Edenflowers.Fulfillment.FulfillmentOption

  @option %FulfillmentOption{
    mileage_rate: Decimal.new("0.55"),
    fuel_price: Decimal.new("1.80"),
    fuel_consumption: Decimal.new("7")
  }

  test "costs the drive there and back at the kilometrikorvaus" do
    assert Decimal.equal?(DeliveryCost.mileage(@option, 8000), "8.80")
  end

  test "costs the fuel for the drive there and back" do
    assert Decimal.equal?(DeliveryCost.fuel(@option, 8000), "2.02")
  end

  test "is nil until its settings are filled in" do
    assert DeliveryCost.mileage(%{@option | mileage_rate: nil}, 8000) == nil
    assert DeliveryCost.fuel(%{@option | fuel_price: nil}, 8000) == nil
    assert DeliveryCost.fuel(%{@option | fuel_consumption: nil}, 8000) == nil
  end
end
