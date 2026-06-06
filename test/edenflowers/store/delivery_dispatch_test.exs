defmodule Edenflowers.Store.DeliveryDispatchTest do
  use Edenflowers.DataCase
  import Generator

  alias Edenflowers.Store.{
    Driver,
    DeliveryBatch,
    DeliveryRoute,
    DeliveryTrip,
    DeliveryStop,
    DeliveryAttempt
  }

  @today ~D[2026-06-07]

  defp admin_actor, do: %{admin: true}
  defp system_actor, do: %{system: true}

  defp create_batch do
    admin = generate(admin_user())

    Ash.create!(
      DeliveryBatch,
      %{delivery_date: @today, published_by_user_id: admin.id, published_at: DateTime.utc_now()},
      action: :create,
      actor: system_actor()
    )
  end

  defp create_route(driver, opts \\ %{}) do
    attrs =
      Map.merge(%{delivery_date: @today, driver_id: driver.id}, opts)

    Ash.create!(DeliveryRoute, attrs, action: :create, actor: system_actor())
  end

  defp create_trip(route, batch, sequence) do
    Ash.create!(
      DeliveryTrip,
      %{
        delivery_route_id: route.id,
        batch_id: batch.id,
        sequence: sequence,
        distance: 1000,
        driving_duration: 600,
        service_duration: 300,
        published_at: DateTime.utc_now()
      },
      action: :create,
      actor: system_actor()
    )
  end

  defp create_stop(trip, order, sequence) do
    Ash.create!(
      DeliveryStop,
      %{
        delivery_trip_id: trip.id,
        order_id: order.id,
        sequence: sequence,
        leg_distance: 500,
        leg_duration: 300
      },
      action: :create,
      actor: system_actor()
    )
  end

  describe "Driver" do
    test "email is unique" do
      generate(driver(email: "shared@example.com"))

      assert {:error, _} =
               Driver.create(
                 %{name: "Dup", email: "shared@example.com"},
                 actor: admin_actor()
               )
    end

    test "active filter excludes inactive drivers" do
      active = generate(driver(active: true))
      _inactive = generate(driver(active: false))

      ids = Driver.list_active!(actor: admin_actor()) |> Enum.map(& &1.id)
      assert active.id in ids
      assert length(ids) == 1
    end

    test "deactivate and reactivate toggle status without destroying" do
      d = generate(driver(active: true))

      {:ok, d} = Driver.deactivate(d, actor: admin_actor())
      refute d.active

      {:ok, d} = Driver.reactivate(d, actor: admin_actor())
      assert d.active
    end

    test "has no destroy action" do
      refute Ash.Resource.Info.action(Driver, :destroy)
    end

    test "non-admin cannot create a driver" do
      assert {:error, _} = Driver.create(%{name: "X", email: "x@example.com"}, actor: nil)
    end
  end

  describe "DeliveryRoute" do
    test "two routes for the same driver and date are rejected" do
      d = generate(driver())
      create_route(d)

      assert_raise Ash.Error.Invalid, fn -> create_route(d) end
    end

    test "different drivers may each have a route on the same date" do
      d1 = generate(driver())
      d2 = generate(driver())

      assert create_route(d1)
      assert create_route(d2)
    end

    test "by_token_hash finds the route by its stored hash" do
      d = generate(driver())
      route = create_route(d, %{token_hash: "abc123hash"})

      found = DeliveryRoute.by_token_hash!("abc123hash", actor: system_actor())
      assert found.id == route.id
    end
  end

  describe "DeliveryTrip" do
    test "sequence is unique within a route" do
      d = generate(driver())
      route = create_route(d)
      batch = create_batch()
      create_trip(route, batch, 1)

      assert_raise Ash.Error.Invalid, fn -> create_trip(route, batch, 1) end
    end
  end

  describe "DeliveryStop" do
    test "sequence is unique within a trip" do
      d = generate(driver())
      route = create_route(d)
      batch = create_batch()
      trip = create_trip(route, batch, 1)
      order1 = generate(order(fulfillment_method: :delivery))
      order2 = generate(order(fulfillment_method: :delivery))

      create_stop(trip, order1, 1)
      assert_raise Ash.Error.Invalid, fn -> create_stop(trip, order2, 1) end
    end
  end

  describe "DeliveryAttempt" do
    setup do
      d = generate(driver())
      route = create_route(d)
      batch = create_batch()
      trip = create_trip(route, batch, 1)
      order = generate(order(fulfillment_method: :delivery))
      stop = create_stop(trip, order, 1)
      %{stop: stop}
    end

    defp attempt(stop, attrs) do
      base = %{
        delivery_stop_id: stop.id,
        recorded_at: DateTime.utc_now(),
        actor_kind: :driver_link
      }

      Ash.create(DeliveryAttempt, Map.merge(base, attrs), action: :create, actor: system_actor())
    end

    test "delivered attempt requires a method", %{stop: stop} do
      assert {:error, _} = attempt(stop, %{outcome: :delivered})
      assert {:ok, _} = attempt(stop, %{outcome: :delivered, delivered_method: :handed_to_recipient})
    end

    test "failed attempt requires a reason", %{stop: stop} do
      assert {:error, _} = attempt(stop, %{outcome: :failed})
      assert {:ok, _} = attempt(stop, %{outcome: :failed, failure_reason: :recipient_unavailable})
    end

    test "method 'other' requires a note", %{stop: stop} do
      assert {:error, _} = attempt(stop, %{outcome: :delivered, delivered_method: :other})

      assert {:ok, _} =
               attempt(stop, %{outcome: :delivered, delivered_method: :other, note: "left with neighbour"})
    end

    test "admin-entered attempt must record the acting admin", %{stop: stop} do
      assert {:error, _} =
               attempt(stop, %{outcome: :delivered, delivered_method: :handed_to_recipient, actor_kind: :admin})

      admin = generate(admin_user())

      assert {:ok, _} =
               attempt(stop, %{
                 outcome: :delivered,
                 delivered_method: :handed_to_recipient,
                 actor_kind: :admin,
                 recorded_by_user_id: admin.id
               })
    end

    test "is append-only (no update or destroy actions)" do
      refute Ash.Resource.Info.action(DeliveryAttempt, :update)
      refute Ash.Resource.Info.action(DeliveryAttempt, :destroy)
    end

    test "multiple attempts per stop are allowed for retries", %{stop: stop} do
      assert {:ok, _} = attempt(stop, %{outcome: :failed, failure_reason: :recipient_unavailable})

      assert {:ok, _} =
               attempt(stop, %{outcome: :delivered, delivered_method: :handed_to_recipient})

      attempts = DeliveryAttempt.for_stop!(stop.id, actor: system_actor())
      assert length(attempts) == 2
    end
  end
end
