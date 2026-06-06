defmodule Edenflowers.DispatchTest do
  use Edenflowers.DataCase
  import Generator

  alias Edenflowers.Dispatch
  alias Edenflowers.HereTourPlanning.{Assignment, Plan, Stop}
  alias Edenflowers.Store.{DeliveryAttempt, DeliveryRoute, DeliveryStop, DeliveryTrip, Order}
  alias Edenflowers.Workers.SendDriverRouteEmail

  @date ~D[2026-06-07]

  defp delivery_order do
    generate(
      order(
        state: :placed,
        payment_status: :paid,
        fulfillment_status: :pending,
        fulfillment_method: :delivery,
        fulfillment_date: @date,
        position: "63.1,21.6"
      )
    )
  end

  defp assignment(driver, orders) do
    stops =
      orders
      |> Enum.with_index(1)
      |> Enum.map(fn {order, i} ->
        %Stop{order_id: order.id, sequence: i, leg_distance: 1000 * i, leg_duration: 600}
      end)

    %Assignment{
      vehicle_id: driver.id,
      stops: stops,
      total_distance: 1000 * length(orders),
      total_driving_duration: 600 * length(orders),
      total_service_duration: 300 * length(orders)
    }
  end

  defp publish(assignments, opts \\ %{}) do
    admin = generate(admin_user())

    Dispatch.publish(
      %Plan{assignments: assignments},
      Map.merge(%{delivery_date: @date, published_by_user_id: admin.id}, opts)
    )
  end

  describe "publish/2" do
    test "persists routes, trips, and ordered stops together" do
      driver = generate(driver())
      o1 = delivery_order()
      o2 = delivery_order()

      {:ok, result} = publish([assignment(driver, [o1, o2])])

      assert [entry] = result.routes
      assert entry.new?
      assert is_binary(entry.raw_token)

      route = DeliveryRoute.get_by_id!(entry.route.id, actor: %{admin: true}, load: [trips: [:stops]])
      assert [trip] = route.trips
      assert trip.sequence == 1
      assert Enum.map(trip.stops, & &1.order_id) == [o1.id, o2.id]
      assert Enum.map(trip.stops, & &1.sequence) == [1, 2]
    end

    test "stores only a token hash, never the raw token" do
      driver = generate(driver())
      {:ok, result} = publish([assignment(driver, [delivery_order()])])

      entry = hd(result.routes)
      stored = DeliveryRoute.by_token_hash!(Dispatch.hash_token(entry.raw_token), actor: %{system: true})
      assert stored.id == entry.route.id
      assert stored.token_hash == Dispatch.hash_token(entry.raw_token)
      refute stored.token_hash == entry.raw_token
    end

    test "creates one daily route per driver across the batch" do
      d1 = generate(driver())
      d2 = generate(driver())

      {:ok, result} = publish([assignment(d1, [delivery_order()]), assignment(d2, [delivery_order()])])

      assert length(result.routes) == 2
      assert DeliveryRoute.for_date!(@date, actor: %{admin: true}) |> length() == 2
    end

    test "enqueues one route email per newly created external route" do
      driver = generate(driver())
      {:ok, result} = publish([assignment(driver, [delivery_order()])])

      assert_enqueued(worker: SendDriverRouteEmail, args: %{delivery_route_id: hd(result.routes).route.id})
    end

    test "appends a supplemental trip to an existing daily route without a second email" do
      driver = generate(driver())
      {:ok, _first} = publish([assignment(driver, [delivery_order()])])

      Oban.drain_queue(queue: :default)

      {:ok, second} =
        publish([assignment(driver, [delivery_order()])], %{
          return_legs: %{driver.id => %{distance: 2500, duration: 400}}
        })

      entry = hd(second.routes)
      refute entry.new?
      refute entry.raw_token

      route = DeliveryRoute.get_by_id!(entry.route.id, actor: %{admin: true}, load: [:trips])
      assert Enum.map(route.trips, & &1.sequence) == [1, 2]

      supplemental = Enum.find(route.trips, &(&1.sequence == 2))
      assert supplemental.return_leg_distance == 2500
      assert supplemental.return_leg_duration == 400

      # No new email job for the already-emailed route.
      refute_enqueued(worker: SendDriverRouteEmail, args: %{delivery_route_id: entry.route.id})
    end

    test "rolls back entirely when an order is already assigned to an active route" do
      driver = generate(driver())
      order = delivery_order()
      {:ok, _} = publish([assignment(driver, [order])])

      other_driver = generate(driver())
      route_count_before = DeliveryRoute.for_date!(@date, actor: %{admin: true}) |> length()

      assert {:error, {:orders_already_assigned, ids}} = publish([assignment(other_driver, [order])])
      assert order.id in ids

      # The failed publication left no new route behind.
      assert DeliveryRoute.for_date!(@date, actor: %{admin: true}) |> length() == route_count_before
      assert DeliveryStop |> Ash.read!(authorize?: false) |> length() == 1
      assert DeliveryTrip |> Ash.read!(authorize?: false) |> length() == 1
    end
  end

  describe "record_outcome/2" do
    defp store_today, do: DateTime.now!("Europe/Helsinki") |> DateTime.to_date()

    defp publish_stop(date) do
      driver = generate(driver())
      order = generate_delivery_order(date)
      admin = generate(admin_user())

      assignment = %Assignment{
        vehicle_id: driver.id,
        stops: [%Stop{order_id: order.id, sequence: 1, leg_distance: 1000, leg_duration: 600}],
        total_distance: 1000,
        total_driving_duration: 600,
        total_service_duration: 300
      }

      {:ok, _} =
        Dispatch.publish(%Plan{assignments: [assignment]}, %{delivery_date: date, published_by_user_id: admin.id})

      {DeliveryStop |> Ash.read!(authorize?: false) |> hd(), order}
    end

    defp generate_delivery_order(date) do
      generate(
        order(
          state: :placed,
          payment_status: :paid,
          fulfillment_status: :pending,
          fulfillment_method: :delivery,
          fulfillment_date: date,
          position: "63.1,21.6"
        )
      )
    end

    test "a delivered outcome creates an attempt and fulfils the order" do
      {stop, order} = publish_stop(store_today())

      {:ok, attempt} =
        Dispatch.record_outcome(stop.id, %{
          outcome: :delivered,
          delivered_method: :handed_to_recipient,
          actor_kind: :driver_link
        })

      assert attempt.outcome == :delivered
      assert Order.get_by_id!(order.id, authorize?: false).fulfillment_status == :fulfilled
    end

    test "records an admin-entered outcome with the acting admin" do
      {stop, _order} = publish_stop(store_today())
      admin = generate(admin_user())

      {:ok, attempt} =
        Dispatch.record_outcome(stop.id, %{
          outcome: :failed,
          failure_reason: :recipient_unavailable,
          actor_kind: :admin,
          recorded_by_user_id: admin.id
        })

      assert attempt.actor_kind == :admin
      assert attempt.recorded_by_user_id == admin.id
    end

    test "rejects an outcome once the route's date has passed" do
      {stop, order} = publish_stop(Date.add(store_today(), -1))

      assert {:error, :expired} =
               Dispatch.record_outcome(stop.id, %{
                 outcome: :delivered,
                 delivered_method: :handed_to_recipient,
                 actor_kind: :driver_link
               })

      assert Order.get_by_id!(order.id, authorize?: false).fulfillment_status == :pending
      assert DeliveryAttempt |> Ash.read!(authorize?: false) == []
    end
  end
end
