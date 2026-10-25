defmodule Edenflowers.Orders.CustomerStatusTest do
  use ExUnit.Case, async: true

  alias Edenflowers.Orders.Order
  alias Edenflowers.ShopTime

  defp status(overrides), do: calculate(:customer_status, overrides)

  defp calculate(calculation, overrides) do
    refs =
      Map.merge(
        %{
          payment_status: :paid,
          fulfillment_status: :pending,
          fulfillment_method: :delivery,
          fulfillment_date: ~D[2026-06-10]
        },
        Map.new(overrides)
      )

    {:ok, value} = Ash.calculate(Order, calculation, refs: refs)
    value
  end

  test "names the outcome once an order is fulfilled" do
    assert status(fulfillment_status: :fulfilled) == :delivered
    assert status(fulfillment_status: :fulfilled, fulfillment_method: :pickup) == :collected
  end

  test "looks forward to a fulfillment date still to come" do
    date = Date.add(ShopTime.today(), 3)

    assert status(fulfillment_date: date) == :arriving
    assert status(fulfillment_date: date, fulfillment_method: :pickup) == :for_pickup
  end

  test "says today when the order lands today" do
    assert status(fulfillment_date: ShopTime.today()) == :arriving_today
    assert status(fulfillment_date: ShopTime.today(), fulfillment_method: :pickup) == :ready_today
  end

  test "never claims delivery for a past date Jennie hasn't marked fulfilled" do
    date = Date.add(ShopTime.today(), -3)

    assert status(fulfillment_date: date) == :delivery_scheduled
    assert status(fulfillment_date: date, fulfillment_method: :pickup) == :pickup_scheduled
  end

  test "reports a refund ahead of anything else" do
    assert status(payment_status: :refunded, fulfillment_status: :fulfilled) == :refunded
  end

  test "falls back to confirmed when there is no fulfillment date" do
    assert status(fulfillment_date: nil) == :confirmed
  end

  test "an order is upcoming while it is still to come, today included" do
    assert calculate(:upcoming?, fulfillment_date: ShopTime.today())
    assert calculate(:upcoming?, fulfillment_date: nil)
    refute calculate(:upcoming?, fulfillment_date: Date.add(ShopTime.today(), -1))
    refute calculate(:upcoming?, fulfillment_status: :fulfilled, fulfillment_date: ShopTime.today())
    refute calculate(:upcoming?, payment_status: :refunded, fulfillment_date: ShopTime.today())
  end
end
