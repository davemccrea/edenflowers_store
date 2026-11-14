defmodule Edenflowers.Orders.DeliveryRunTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Orders

  setup do
    {:ok, admin: generate(admin_user()), today: Edenflowers.ShopTime.today()}
  end

  defp delivery(date, attrs \\ []) do
    generate(
      order(
        [
          state: :placed,
          customer_name: "Someone",
          fulfillment_method: :delivery,
          fulfillment_date: date,
          fulfillment_status: :pending,
          position: "63.09,21.61"
        ] ++ attrs
      )
    )
  end

  defp route_positions(admin, orders) do
    for order <- orders, do: Orders.get_order_by_id!(order.id, actor: admin).route_position
  end

  test "numbers today's deliveries in the order given and takes earlier stops it leaves out off the run",
       %{admin: admin, today: today} do
    [a, b, c] = for _ <- 1..3, do: delivery(today)
    unplaced = delivery(today, position: nil)

    planned = for minute <- [10, 20, 30], do: DateTime.new!(today, Time.new!(9, minute, 0), "Etc/UTC")
    back = DateTime.new!(today, ~T[10:00:00], "Etc/UTC")

    :ok =
      Orders.start_delivery_run(today, [b.id, a.id, c.id], %{planned_at: planned, planned_back_at: back}, actor: admin)

    assert route_positions(admin, [b, a, c]) == [1, 2, 3]
    stop = Orders.get_order_by_id!(a.id, actor: admin)
    assert {stop.route_planned_at, stop.route_planned_back_at} == {Enum.at(planned, 1), back}

    # A second run without c: c leaves the run, and a delivery a route can't visit never joins it.
    :ok = Orders.start_delivery_run(today, [a.id, unplaced.id, b.id], actor: admin)
    assert route_positions(admin, [a, b, c, unplaced]) == [1, 2, nil, nil]
  end

  test "ends the day's run when given no stops, leaving the orders as they were", %{admin: admin, today: today} do
    [a, b] = for _ <- 1..2, do: delivery(today, fulfillment_status: :ready)
    :ok = Orders.start_delivery_run(today, [a.id, b.id], actor: admin)

    :ok = Orders.start_delivery_run(today, [], actor: admin)

    assert route_positions(admin, [a, b]) == [nil, nil]
    assert Orders.get_order_by_id!(a.id, actor: admin).fulfillment_status == :ready
  end

  test "only starts on its day", %{admin: admin, today: today} do
    order = delivery(Date.add(today, 1))

    assert {:error, %Ash.Error.Invalid{}} = Orders.start_delivery_run(Date.add(today, 1), [order.id], actor: admin)
    assert route_positions(admin, [order]) == [nil]
  end
end
