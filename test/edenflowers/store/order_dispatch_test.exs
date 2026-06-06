defmodule Edenflowers.Store.OrderDispatchTest do
  use Edenflowers.DataCase
  import Generator

  alias Edenflowers.Store.{Order, DeliveryBatch, DeliveryRoute, DeliveryTrip, DeliveryStop}

  @today ~D[2026-06-07]
  @yesterday ~D[2026-06-06]

  defp admin_actor, do: %{admin: true}
  defp system_actor, do: %{system: true}

  defp eligible_order(opts \\ %{}) do
    base = %{
      state: :placed,
      payment_status: :paid,
      fulfillment_status: :pending,
      fulfillment_method: :delivery,
      fulfillment_date: @today,
      delivery_address: "Some Street 1, 65100 Vaasa",
      position: "63.1,21.6"
    }

    generate(order(Map.merge(base, opts) |> Map.to_list()))
  end

  defp assign_to_route(order, route_date) do
    driver = generate(driver())
    admin = generate(admin_user())

    route =
      Ash.create!(DeliveryRoute, %{delivery_date: route_date, driver_id: driver.id},
        action: :create,
        actor: system_actor()
      )

    batch =
      Ash.create!(
        DeliveryBatch,
        %{delivery_date: route_date, published_by_user_id: admin.id, published_at: DateTime.utc_now()},
        action: :create,
        actor: system_actor()
      )

    trip =
      Ash.create!(
        DeliveryTrip,
        %{
          delivery_route_id: route.id,
          batch_id: batch.id,
          sequence: 1,
          distance: 1,
          driving_duration: 1,
          service_duration: 1,
          published_at: DateTime.utc_now()
        },
        action: :create,
        actor: system_actor()
      )

    Ash.create!(
      DeliveryStop,
      %{delivery_trip_id: trip.id, order_id: order.id, sequence: 1, leg_distance: 1, leg_duration: 1},
      action: :create,
      actor: system_actor()
    )
  end

  describe ":dispatch_eligible" do
    test "returns a paid, pending delivery order for the date" do
      order = eligible_order()
      ids = Order.list_dispatch_eligible!(%{date: @today}, actor: admin_actor()) |> Enum.map(& &1.id)
      assert order.id in ids
    end

    test "excludes pickup, unpaid, fulfilled, and wrong-date orders" do
      eligible = eligible_order()
      _pickup = eligible_order(%{fulfillment_method: :pickup})
      _unpaid = eligible_order(%{payment_status: :pending})
      _fulfilled = eligible_order(%{fulfillment_status: :fulfilled})
      _other_day = eligible_order(%{fulfillment_date: ~D[2026-06-08]})

      ids = Order.list_dispatch_eligible!(%{date: @today}, actor: admin_actor()) |> Enum.map(& &1.id)
      assert ids == [eligible.id]
    end

    test "excludes an order already assigned to a stop on the same date's route" do
      order = eligible_order()
      assign_to_route(order, @today)

      ids = Order.list_dispatch_eligible!(%{date: @today}, actor: admin_actor()) |> Enum.map(& &1.id)
      refute order.id in ids
    end

    test "includes an order whose only stop is on an expired earlier route" do
      order = eligible_order()
      assign_to_route(order, @yesterday)

      ids = Order.list_dispatch_eligible!(%{date: @today}, actor: admin_actor()) |> Enum.map(& &1.id)
      assert order.id in ids
    end
  end

  describe ":mark_delivered" do
    test "marks a pending order fulfilled" do
      order = eligible_order()
      {:ok, order} = Order.mark_delivered(order, actor: system_actor())
      assert order.fulfillment_status == :fulfilled
    end

    test "rejects an already-fulfilled order" do
      order = eligible_order(%{fulfillment_status: :fulfilled})
      assert {:error, _} = Order.mark_delivered(order, actor: system_actor())
    end
  end

  describe ":reschedule_delivery" do
    test "changes only the fulfillment date" do
      order = eligible_order()

      {:ok, rescheduled} =
        Order.reschedule_delivery(order, %{fulfillment_date: ~D[2026-06-10]}, actor: admin_actor())

      assert rescheduled.fulfillment_date == ~D[2026-06-10]
      assert rescheduled.delivery_address == order.delivery_address
      assert rescheduled.position == order.position
    end

    test "rejects an unpaid order" do
      order = eligible_order(%{payment_status: :pending})

      assert {:error, _} =
               Order.reschedule_delivery(order, %{fulfillment_date: ~D[2026-06-10]}, actor: admin_actor())
    end

    test "rejects an order assigned to an active route" do
      order = eligible_order()
      assign_to_route(order, @today)

      assert {:error, _} =
               Order.reschedule_delivery(order, %{fulfillment_date: ~D[2026-06-10]}, actor: admin_actor())
    end

    test "allows rescheduling an order whose only route is expired" do
      order = eligible_order()
      assign_to_route(order, @yesterday)

      assert {:ok, _} =
               Order.reschedule_delivery(order, %{fulfillment_date: ~D[2026-06-10]}, actor: admin_actor())
    end
  end
end
