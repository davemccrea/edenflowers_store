defmodule Edenflowers.Delivery.RouteStopTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Delivery.{Route, RouteStop}
  alias Edenflowers.Store.Order

  @today ~D[2026-06-07]

  defp published_stop(order_overrides \\ []) do
    order = generate(order(Keyword.merge([fulfillment_status: :pending], order_overrides)))
    driver = generate(driver())

    route =
      Route.publish!(
        %{
          date: @today,
          driver_id: driver.id,
          stops: [
            %{
              sequence: 1,
              order_id: order.id,
              order_reference: order.order_reference,
              leg_distance_m: 2_000,
              leg_duration_s: 300,
              products: []
            }
          ]
        },
        authorize?: false
      )

    [stop] = Ash.load!(route, :route_stops, authorize?: false).route_stops
    {order, route, stop}
  end

  test "delivered sets the status and marks the order fulfilled" do
    {order, _route, stop} = published_stop()

    assert {:ok, stop} =
             RouteStop.record_delivered(stop, %{delivery_method: :handed_to_recipient}, authorize?: false)

    assert stop.status == :delivered
    assert stop.delivery_method == :handed_to_recipient
    assert stop.outcome_recorded_at

    assert Order.get_by_id!(order.id, authorize?: false).fulfillment_status == :fulfilled
  end

  test "failed sets the status and leaves the order pending" do
    {order, _route, stop} = published_stop()

    assert {:ok, stop} =
             RouteStop.record_failed(stop, %{failure_reason: :recipient_unavailable}, authorize?: false)

    assert stop.status == :failed
    assert stop.failure_reason == :recipient_unavailable

    assert Order.get_by_id!(order.id, authorize?: false).fulfillment_status == :pending
  end

  test "delivered requires a method" do
    {_order, _route, stop} = published_stop()
    assert {:error, _} = RouteStop.record_delivered(stop, %{}, authorize?: false)
  end

  test "failed requires a reason" do
    {_order, _route, stop} = published_stop()
    assert {:error, _} = RouteStop.record_failed(stop, %{}, authorize?: false)
  end

  test "the \"other\" method requires a note" do
    {_order, _route, stop} = published_stop()

    assert {:error, _} = RouteStop.record_delivered(stop, %{delivery_method: :other}, authorize?: false)

    assert {:ok, delivered} =
             RouteStop.record_delivered(
               stop,
               %{delivery_method: :other, outcome_note: "Left with neighbour"},
               authorize?: false
             )

    assert delivered.outcome_note == "Left with neighbour"
  end

  test "the \"other\" reason requires a note" do
    {_order, _route, stop} = published_stop()

    assert {:error, _} = RouteStop.record_failed(stop, %{failure_reason: :other}, authorize?: false)

    assert {:ok, _failed} =
             RouteStop.record_failed(
               stop,
               %{failure_reason: :other, outcome_note: "Wrong town entirely"},
               authorize?: false
             )
  end

  test "retrying a failed stop overwrites the outcome and fulfills the order" do
    {order, _route, stop} = published_stop()

    {:ok, failed} =
      RouteStop.record_failed(stop, %{failure_reason: :recipient_unavailable}, authorize?: false)

    assert {:ok, delivered} =
             RouteStop.record_delivered(failed, %{delivery_method: :handed_to_recipient}, authorize?: false)

    assert delivered.status == :delivered
    assert delivered.failure_reason == nil
    assert Order.get_by_id!(order.id, authorize?: false).fulfillment_status == :fulfilled
  end

  test "recording an outcome broadcasts on the route's topic" do
    {_order, route, stop} = published_stop()
    topic = "route_stop:outcome:#{route.id}"
    EdenflowersWeb.Endpoint.subscribe(topic)

    RouteStop.record_delivered(stop, %{delivery_method: :handed_to_recipient}, authorize?: false)

    assert_receive %Phoenix.Socket.Broadcast{topic: ^topic}
  end
end
