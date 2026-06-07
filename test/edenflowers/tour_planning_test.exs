defmodule Edenflowers.TourPlanningTest do
  use ExUnit.Case, async: true

  alias Edenflowers.TourPlanning

  # Mirrors the documented HERE Tour Planning v3 solution shape: the first stop in a
  # tour is the shop departure (no delivery activity); each later stop carries a
  # cumulative `distance` from the start and arrival/departure timestamps.
  defp problem do
    %{
      stops: [
        %{id: "order-1", position: "63.1157,21.61864", handling_seconds: 300},
        %{id: "order-2", position: "63.03232,21.54662", handling_seconds: 300}
      ],
      drivers: [%{id: "spike-1"}]
    }
  end

  defp solution_body do
    %{
      "tours" => [
        %{
          "typeId" => "driver-spike-1",
          "stops" => [
            %{
              "distance" => 0,
              "time" => %{"arrival" => "2026-06-07T08:00:00Z", "departure" => "2026-06-07T08:00:00Z"},
              "activities" => [%{"type" => "departure", "jobId" => "departure"}]
            },
            %{
              "distance" => 1651,
              "time" => %{"arrival" => "2026-06-07T08:05:00Z", "departure" => "2026-06-07T08:10:00Z"},
              "activities" => [%{"type" => "delivery", "jobId" => "order-1"}]
            },
            %{
              "distance" => 4000,
              "time" => %{"arrival" => "2026-06-07T08:20:00Z", "departure" => "2026-06-07T08:25:00Z"},
              "activities" => [%{"type" => "delivery", "jobId" => "order-2"}]
            }
          ]
        }
      ]
    }
  end

  describe "parse_solution/2" do
    test "maps tours to per-driver routes with per-leg and total metrics" do
      assert {:ok, [route]} = TourPlanning.parse_solution(solution_body(), problem())

      assert route.driver_id == "spike-1"
      assert [stop1, stop2] = route.stops

      assert stop1.stop_id == "order-1"
      assert stop1.sequence == 1
      assert stop1.leg_from_previous == %{distance_m: 1651, duration_s: 300}

      assert stop2.stop_id == "order-2"
      assert stop2.sequence == 2
      assert stop2.leg_from_previous == %{distance_m: 2349, duration_s: 600}
    end

    test "totals are leg sums, with duration adding per-stop handling" do
      assert {:ok, [route]} = TourPlanning.parse_solution(solution_body(), problem())

      assert route.total_distance_m == 4000
      assert route.total_driving_s == 900
      # driving 900 + handling (2 x 300) = 1500
      assert route.total_duration_s == 1500
    end

    test "returns {:error, :unassigned} when HERE leaves any order unplaced" do
      body = Map.put(solution_body(), "unassigned", [%{"jobId" => "order-2", "reasons" => []}])

      assert {:error, :unassigned} = TourPlanning.parse_solution(body, problem())
    end
  end

  describe "build_problem/1" do
    test "maps drivers to open-route vehicles and stops to delivery jobs" do
      problem = TourPlanning.build_problem(problem())

      assert [vehicle] = problem.fleet.types
      assert vehicle.id == "driver-spike-1"
      assert [shift] = vehicle.shifts
      assert shift.start.location == %{lat: 63.1243488, lng: 21.5974075}
      # Open route: no end location, so the route finishes at the last delivery.
      refute Map.has_key?(shift, :end)

      assert [job1, job2] = problem.plan.jobs
      assert job1.id == "order-1"
      assert [%{places: [%{duration: 300}], demand: [1]}] = job1.tasks.deliveries
      assert job2.id == "order-2"

      assert problem.objectives == [
               %{type: "minimizeUnassigned"},
               %{type: "minimizeCost"}
             ]
    end

    test "every available driver becomes a vehicle (HERE chooses how many to use)" do
      stops = for n <- 1..7, do: %{id: "order-#{n}", position: "63.1,21.6", handling_seconds: 300}
      drivers = for n <- 1..3, do: %{id: "d#{n}"}

      problem = TourPlanning.build_problem(%{stops: stops, drivers: drivers})

      assert length(problem.fleet.types) == 3
    end
  end
end
