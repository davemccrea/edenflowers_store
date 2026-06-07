defmodule Edenflowers.Store.Order.EligibleForDeliveryTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Store.Order

  @today ~D[2026-06-07]

  defp eligible_order(overrides) do
    defaults = [
      state: :placed,
      payment_status: :paid,
      fulfillment_status: :pending,
      fulfillment_method: :delivery,
      fulfillment_date: @today,
      position: "63.0951,21.6165",
      ordered_at: DateTime.utc_now()
    ]

    generate(order(Keyword.merge(defaults, overrides)))
  end

  defp ids(orders), do: Enum.map(orders, & &1.id) |> MapSet.new()

  test "returns today's placed, paid, pending delivery orders with a position" do
    eligible = eligible_order(order_reference: "EF-OK")

    assert {:ok, orders} = Order.list_eligible_for_delivery(%{date: @today}, authorize?: false)
    assert ids(orders) == MapSet.new([eligible.id])
  end

  test "excludes orders that are not eligible" do
    eligible_order(order_reference: "EF-OK")

    eligible_order(payment_status: :pending)
    eligible_order(fulfillment_status: :fulfilled)
    eligible_order(fulfillment_method: :pickup)
    eligible_order(fulfillment_date: Date.add(@today, 1))
    eligible_order(position: nil)
    eligible_order(state: :payment)

    assert {:ok, orders} = Order.list_eligible_for_delivery(%{date: @today}, authorize?: false)
    assert Enum.map(orders, & &1.order_reference) == ["EF-OK"]
  end

  test "defaults the date to today in Europe/Helsinki" do
    today = DateTime.now!("Europe/Helsinki") |> DateTime.to_date()
    eligible = eligible_order(fulfillment_date: today, order_reference: "EF-TODAY")

    assert {:ok, orders} = Order.list_eligible_for_delivery(%{}, authorize?: false)
    assert eligible.id in Enum.map(orders, & &1.id)
  end
end
