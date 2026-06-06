defmodule Edenflowers.HereTourPlanningTest do
  use ExUnit.Case, async: true

  alias Edenflowers.HereTourPlanning
  alias Edenflowers.HereTourPlanning.Input

  @shop %{lat: 63.1243488, lng: 21.5974075}

  defp fixture(name) do
    Path.join([__DIR__, "..", "support", "fixtures", "here_tour_planning", name])
    |> File.read!()
    |> Jason.decode!()
  end

  defp input(order_ids, vehicle_ids) do
    %Input{
      orders: Enum.map(order_ids, &%{id: &1, lat: 63.1, lng: 21.6}),
      vehicle_ids: vehicle_ids,
      shop: @shop,
      date: ~D[2026-06-07]
    }
  end

  describe "build_problem/1" do
    test "builds one equivalent car per vehicle and one delivery job per order" do
      problem = HereTourPlanning.build_problem(input(["order-1", "order-2"], ["driver-a"]))

      assert [type] = problem.fleet.types
      assert type.id == "driver-a"
      assert type.profile == "car"
      assert [shift] = type.shifts
      assert shift.start.location == %{lat: @shop.lat, lng: @shop.lng}
      assert String.contains?(shift.start.time, "2026-06-07T08:00:00")

      assert length(problem.plan.jobs) == 2
      assert Enum.map(problem.plan.jobs, & &1.id) == ["order-1", "order-2"]

      assert [%{type: "minimize-unassigned"} | _] = problem.objectives
    end

    test "service duration is applied to each delivery place" do
      problem =
        HereTourPlanning.build_problem(%{input(["order-1"], ["driver-a"]) | service_duration: 300})

      job = hd(problem.plan.jobs)
      place = job.tasks.deliveries |> hd() |> Map.get(:places) |> hd()
      assert place.duration == 300
    end
  end

  describe "parse_plan/2 — one driver" do
    test "orders the stops and computes leg and route totals" do
      {:ok, plan} =
        HereTourPlanning.parse_plan(fixture("one_driver.json"), input(["order-1", "order-2"], ["driver-a"]))

      assert [assignment] = plan.assignments
      assert assignment.vehicle_id == "driver-a"

      assert [stop1, stop2] = assignment.stops

      assert {stop1.order_id, stop1.sequence, stop1.leg_distance, stop1.leg_duration} ==
               {"order-1", 1, 3000, 600}

      assert {stop2.order_id, stop2.sequence, stop2.leg_distance, stop2.leg_duration} ==
               {"order-2", 2, 4000, 600}

      assert assignment.total_distance == 7000
      assert assignment.total_driving_duration == 1200
      assert assignment.total_service_duration == 600
    end
  end

  describe "parse_plan/2 — multiple drivers" do
    test "assigns orders across vehicles" do
      {:ok, plan} =
        HereTourPlanning.parse_plan(
          fixture("multi_driver.json"),
          input(["order-1", "order-2", "order-3"], ["driver-a", "driver-b"])
        )

      by_vehicle = Map.new(plan.assignments, &{&1.vehicle_id, Enum.map(&1.stops, fn s -> s.order_id end)})
      assert by_vehicle["driver-a"] == ["order-1", "order-2"]
      assert by_vehicle["driver-b"] == ["order-3"]
    end
  end

  describe "parse_plan/2 — rejections" do
    test "rejects a response with unassigned jobs" do
      assert {:error, {:unassigned, ["order-2"]}} =
               HereTourPlanning.parse_plan(
                 fixture("unassigned.json"),
                 input(["order-1", "order-2"], ["driver-a"])
               )
    end

    test "rejects a response missing an expected order" do
      assert {:error, :missing_assignment} =
               HereTourPlanning.parse_plan(
                 fixture("one_driver.json"),
                 input(["order-1", "order-2", "order-3"], ["driver-a"])
               )
    end

    test "rejects a response referencing an unknown vehicle" do
      assert {:error, {:unknown_vehicle, "driver-a"}} =
               HereTourPlanning.parse_plan(
                 fixture("one_driver.json"),
                 input(["order-1", "order-2"], ["driver-z"])
               )
    end

    test "rejects a malformed response with no tours" do
      assert {:error, :malformed_response} =
               HereTourPlanning.parse_plan(%{"unassigned" => []}, input(["order-1"], ["driver-a"]))
    end
  end
end
