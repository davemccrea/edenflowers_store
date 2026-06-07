defmodule Edenflowers.Delivery.RouteTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Delivery.{Route, RouteStop}
  alias Edenflowers.Store.Order

  @today ~D[2026-06-07]

  defp eligible_order(overrides \\ []) do
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

  defp stop_args(order, overrides \\ []) do
    Enum.into(overrides, %{
      sequence: 1,
      order_id: order.id,
      order_reference: order.order_reference,
      recipient_name: "Alice",
      recipient_phone: "+358401234567",
      delivery_address: "Some Street 1",
      delivery_instructions: "Ring twice",
      card_message: "Happy Birthday",
      products: [%{"name" => "Roses", "quantity" => 2}],
      position: order.position,
      leg_distance_m: 2_000,
      leg_duration_s: 300
    })
  end

  test "publish persists a route with its ordered, snapshotted stops" do
    order = eligible_order(order_reference: "EF-PUB")
    driver = generate(driver(name: "Dana"))

    assert {:ok, route} =
             Route.publish(%{date: @today, driver_id: driver.id, stops: [stop_args(order)]},
               authorize?: false
             )

    route = Ash.load!(route, [:route_stops, :driver], authorize?: false)

    assert route.date == @today
    assert route.published_at
    assert route.driver.name == "Dana"

    assert [stop] = route.route_stops
    assert stop.order_id == order.id
    assert stop.order_reference == "EF-PUB"
    assert stop.recipient_name == "Alice"
    assert stop.delivery_address == "Some Street 1"
    assert stop.card_message == "Happy Birthday"
    assert stop.products == [%{"name" => "Roses", "quantity" => 2}]
    assert stop.status == :pending
    assert stop.leg_distance_m == 2_000
  end

  test "an order on a published route drops out of eligibility" do
    published = eligible_order(order_reference: "EF-DONE")
    still_open = eligible_order(order_reference: "EF-OPEN")
    driver = generate(driver())

    Route.publish!(%{date: @today, driver_id: driver.id, stops: [stop_args(published)]},
      authorize?: false
    )

    assert {:ok, orders} = Order.list_eligible_for_delivery(%{date: @today}, authorize?: false)
    assert Enum.map(orders, & &1.id) == [still_open.id]
  end

  test "publish is atomic — an invalid stop persists nothing" do
    order = eligible_order()
    driver = generate(driver())

    assert {:error, _} =
             Route.publish(
               %{date: @today, driver_id: driver.id, stops: [stop_args(order, leg_distance_m: nil)]},
               authorize?: false
             )

    assert Ash.read!(Route, authorize?: false) == []
    assert Ash.read!(RouteStop, authorize?: false) == []
  end
end
