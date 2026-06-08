defmodule Edenflowers.Geography.TourPlanningTest do
  use ExUnit.Case, async: true

  alias Edenflowers.Geography.TourPlanning.HERE

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
      assert {:ok, [route]} = HERE.parse_solution(solution_body(), problem())

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
      assert {:ok, [route]} = HERE.parse_solution(solution_body(), problem())

      assert route.total_distance_m == 4000
      assert route.total_driving_s == 900
      # driving 900 + handling (2 x 300) = 1500
      assert route.total_duration_s == 1500
    end

    test "returns {:error, :unassigned} when HERE leaves any order unplaced" do
      body = Map.put(solution_body(), "unassigned", [%{"jobId" => "order-2", "reasons" => []}])

      assert {:error, :unassigned} = HERE.parse_solution(body, problem())
    end

    test "returns {:error, :unassigned} when a requested order is absent from the tours" do
      body =
        update_in(solution_body(), ["tours", Access.at(0), "stops"], fn [departure, first, _second] ->
          [departure, first]
        end)

      assert {:error, :unassigned} = HERE.parse_solution(body, problem())
    end

    test "keeps every delivery when HERE groups multiple jobs into one stop" do
      body =
        update_in(solution_body(), ["tours", Access.at(0), "stops"], fn [departure, first, second] ->
          grouped =
            first
            |> Map.put("activities", first["activities"] ++ second["activities"])

          [departure, grouped]
        end)

      assert {:ok, [route]} = HERE.parse_solution(body, problem())

      assert [
               %{
                 stop_id: "order-1",
                 sequence: 1,
                 leg_from_previous: %{distance_m: 1651, duration_s: 300}
               },
               %{
                 stop_id: "order-2",
                 sequence: 2,
                 leg_from_previous: %{distance_m: 0, duration_s: 0}
               }
             ] = route.stops

      assert route.total_distance_m == 1651
      assert route.total_driving_s == 300
      assert route.total_duration_s == 900
    end
  end

  describe "build_problem/1" do
    test "maps drivers to open-route vehicles, stops to jobs, and defaults to cheapest" do
      problem = HERE.build_problem(problem())

      assert [vehicle] = problem.fleet.types
      assert vehicle.id == "driver-spike-1"
      assert [shift] = vehicle.shifts
      assert shift.start.location == %{lat: 63.1243488, lng: 21.5974075}
      # Open route: no end location, so the route finishes at the last delivery.
      refute Map.has_key?(shift, :end)

      assert [%{ignoreRouteViolations: ["all"]}] = problem.fleet.profiles

      assert [job1, job2] = problem.plan.jobs
      assert job1.id == "order-1"
      assert [%{places: [%{duration: 300}], demand: [1]}] = job1.tasks.deliveries
      assert job2.id == "order-2"

      assert problem.objectives == [
               %{type: "minimizeUnassigned"},
               %{type: "minimizeCost"}
             ]

      refute Map.has_key?(problem, :advancedObjectives)
    end

    test "balanced enables advanced objectives and balances route duration before minimizing cost" do
      problem = HERE.build_problem(Map.put(problem(), :strategy, :balanced))

      assert problem.advancedObjectives == [
               [%{type: "minimizeUnassigned"}],
               [%{type: "maximizeTours"}],
               [%{type: "balanceDuration", options: %{threshold: 0.1}}],
               [%{type: "minimizeCost"}]
             ]

      assert problem.configuration == %{experimentalFeatures: ["advancedObjectives"]}
      refute Map.has_key?(problem, :objectives)
    end

    test "fastest maximizes parallel routes before minimizing total duration and cost" do
      problem = HERE.build_problem(Map.put(problem(), :strategy, :fastest))

      assert problem.objectives == [
               %{type: "minimizeUnassigned"},
               %{type: "optimizeTourCount", action: "maximize"},
               %{type: "minimizeDuration"},
               %{type: "minimizeCost"}
             ]

      refute Map.has_key?(problem, :advancedObjectives)
    end

    test "every available driver becomes a vehicle (HERE chooses how many to use)" do
      stops = for n <- 1..7, do: %{id: "order-#{n}", position: "63.1,21.6", handling_seconds: 300}
      drivers = for n <- 1..3, do: %{id: "d#{n}"}

      problem = HERE.build_problem(%{stops: stops, drivers: drivers})

      assert length(problem.fleet.types) == 3
    end
  end
end
