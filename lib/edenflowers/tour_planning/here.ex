defmodule Edenflowers.TourPlanning.HERE do
  @moduledoc """
  HERE Tour Planning adapter (synchronous `/v3/problems` endpoint).

  Maps each driver to a vehicle whose shift starts at the shop with no end location
  (open route), and each stop to a delivery job carrying its handling time.

  Supports three per-run optimization strategies:

  * `:cheapest` places every order, then minimizes total driving distance.
  * `:balanced` uses as many selected drivers as possible, balances route duration,
    then minimizes cost within those constraints.
  * `:fastest` uses as many selected drivers as possible, then minimizes the sum of all
    route durations and cost.

  Routes are open (no return to the shop). Under `:cheapest`, selected drivers are an
  available pool and HERE may leave some unused. Under `:balanced`, the selected drivers
  are the intended workforce, limited only by there being fewer deliveries than drivers.
  """

  @behaviour Edenflowers.TourPlanning.Behaviour

  require Logger

  @shop_position "63.1243488,21.5974075"
  @profile "delivery_car"
  @endpoint "https://tourplanning.hereapi.com/v3/problems"

  # HERE requires a capacity/demand dimension. We don't constrain by capacity, so every
  # vehicle gets a capacity well above any realistic daily order count and each delivery
  # demands one unit.
  @vehicle_capacity 1000

  @impl true
  def solve(%{stops: _, drivers: _} = problem_input) do
    with {:ok, body} <- post(build_problem(problem_input)) do
      parse_solution(body, problem_input)
    end
  end

  @doc """
  POSTs an already-built problem and returns the raw decoded response body.

  Public for the `eden.tour_planning_spike` task, which inspects the raw HERE
  response to confirm field names before this adapter is relied on.
  """
  def post(problem) do
    case Req.post(@endpoint, params: [apiKey: api_key()], json: problem) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.error("TourPlanning returned status #{status}: #{inspect(body)}")
        {:error, :tour_planning_failed}

      other ->
        Logger.error("TourPlanning request failed: #{inspect(other)}")
        {:error, :tour_planning_failed}
    end
  end

  @doc "Builds the HERE Tour Planning problem JSON from the behaviour's problem input."
  def build_problem(%{stops: stops, drivers: drivers} = problem) do
    problem
    |> Map.get(:strategy, :cheapest)
    |> objectives()
    |> then(fn objective_fields ->
      %{
        fleet: %{
          types: Enum.map(drivers, &vehicle_type/1),
          profiles: [
            %{
              name: @profile,
              type: "car",
              # Last-mile addresses can sit behind pedestrian or no-through road segments.
              # Drivers can park nearby and complete that final stretch on foot.
              ignoreRouteViolations: ["all"]
            }
          ]
        },
        plan: %{jobs: Enum.map(stops, &job/1)}
      }
      |> Map.merge(objective_fields)
    end)
  end

  # Exact workload balancing is exposed by HERE through advanced objectives (an alpha API).
  # Keep all strategy-to-payload mapping isolated here so the planner and solver boundary
  # remain stable if HERE changes the objective schema.
  defp objectives(:cheapest) do
    %{
      objectives: [
        %{type: "minimizeUnassigned"},
        %{type: "minimizeCost"}
      ]
    }
  end

  defp objectives(:balanced) do
    %{
      configuration: %{experimentalFeatures: ["advancedObjectives"]},
      advancedObjectives: [
        [%{type: "minimizeUnassigned"}],
        [%{type: "maximizeTours"}],
        [%{type: "balanceDuration", options: %{threshold: 0.1}}],
        [%{type: "minimizeCost"}]
      ]
    }
  end

  defp objectives(:fastest) do
    %{
      objectives: [
        %{type: "minimizeUnassigned"},
        %{type: "optimizeTourCount", action: "maximize"},
        %{type: "minimizeDuration"},
        %{type: "minimizeCost"}
      ]
    }
  end

  # One vehicle per driver. Cost is driving distance only (no fixed or time cost), so the
  # plan minimises total kilometres. `shift.end` is omitted so the route ends at the last
  # delivery (open route).
  defp vehicle_type(%{id: driver_id}) do
    %{
      id: "driver-#{driver_id}",
      profile: @profile,
      costs: %{fixed: 0.0, distance: 1.0, time: 0.0},
      capacity: [@vehicle_capacity],
      shifts: [%{start: %{time: shift_start(), location: latlng(@shop_position)}}],
      amount: 1
    }
  end

  defp job(%{id: id, position: position, handling_seconds: handling}) do
    %{
      id: id,
      tasks: %{
        deliveries: [
          %{places: [%{location: latlng(position), duration: handling}], demand: [1]}
        ]
      }
    }
  end

  @doc """
  Translates a raw HERE solution body into the behaviour's output, or `{:error, :unassigned}`
  when the solver couldn't place every order. Public so the spike task can parse a raw
  response it has already fetched.
  """
  def parse_solution(%{"unassigned" => [_ | _]}, _problem), do: {:error, :unassigned}
  def parse_solution(body, %{stops: stops}), do: parse_tours(body, stops)

  # Translate HERE tours into the behaviour's output. Each tour's first stop is the
  # shop departure (no job activity); delivery stops carry a cumulative distance from
  # the start, so per-leg distance is the diff between consecutive stops.
  defp parse_tours(%{"tours" => tours}, stops) do
    handling_by_id = Map.new(stops, fn s -> {s.id, s.handling_seconds} end)

    routes =
      Enum.map(tours, fn tour ->
        driver_id = driver_id_from_type(tour["typeId"])
        solved_stops = solved_stops(tour["stops"] || [])
        total_distance = solved_stops |> Enum.map(& &1.leg_from_previous.distance_m) |> Enum.sum()
        total_driving = solved_stops |> Enum.map(& &1.leg_from_previous.duration_s) |> Enum.sum()
        handling = solved_stops |> Enum.map(&Map.get(handling_by_id, &1.stop_id, 0)) |> Enum.sum()

        %{
          driver_id: driver_id,
          stops: solved_stops,
          total_distance_m: total_distance,
          total_driving_s: total_driving,
          total_duration_s: total_driving + handling
        }
      end)

    validate_assigned_stops(routes, stops)
  end

  defp parse_tours(_body, _stops), do: {:error, :tour_planning_failed}

  defp validate_assigned_stops(routes, requested_stops) do
    requested_ids = MapSet.new(requested_stops, & &1.id)
    assigned_ids = routes |> Enum.flat_map(& &1.stops) |> Enum.map(& &1.stop_id)
    assigned_id_set = MapSet.new(assigned_ids)

    cond do
      assigned_id_set == requested_ids and length(assigned_ids) == MapSet.size(requested_ids) ->
        {:ok, routes}

      MapSet.subset?(assigned_id_set, requested_ids) ->
        {:error, :unassigned}

      true ->
        {:error, :tour_planning_failed}
    end
  end

  # Walk the tour's stops in order, threading the previous stop so each delivery's leg
  # is measured from whatever came before it (the shop departure for the first). HERE
  # reports a cumulative distance per stop, so a leg's distance is the diff; a leg's
  # driving time is this stop's arrival minus the previous stop's departure.
  defp solved_stops(here_stops) do
    {solved, _previous_stop} =
      Enum.flat_map_reduce(here_stops, nil, fn here_stop, previous_stop ->
        case delivery_job_ids(here_stop) do
          [] ->
            {[], here_stop}

          job_ids ->
            first_leg = %{
              distance_m: max(cumulative_distance(here_stop) - cumulative_distance(previous_stop), 0),
              duration_s: leg_seconds(previous_stop, here_stop)
            }

            stops_at_location =
              job_ids
              |> Enum.with_index()
              |> Enum.map(fn
                {job_id, 0} -> {job_id, first_leg}
                {job_id, _} -> {job_id, %{distance_m: 0, duration_s: 0}}
              end)

            {stops_at_location, here_stop}
        end
      end)

    solved
    |> Enum.with_index(1)
    |> Enum.map(fn {{job_id, leg}, sequence} ->
      %{stop_id: job_id, sequence: sequence, leg_from_previous: leg}
    end)
  end

  defp delivery_job_ids(%{"activities" => activities}) do
    Enum.flat_map(activities, fn
      %{"type" => "delivery", "jobId" => job_id} -> [job_id]
      _ -> []
    end)
  end

  defp delivery_job_ids(_), do: []

  defp cumulative_distance(%{"distance" => distance}) when is_integer(distance), do: distance
  defp cumulative_distance(_), do: 0

  defp leg_seconds(%{"time" => %{"departure" => departure}}, %{"time" => %{"arrival" => arrival}}) do
    with {:ok, departure_dt, _} <- DateTime.from_iso8601(departure),
         {:ok, arrival_dt, _} <- DateTime.from_iso8601(arrival) do
      max(DateTime.diff(arrival_dt, departure_dt), 0)
    else
      _ -> 0
    end
  end

  defp leg_seconds(_prev, _current), do: 0

  defp driver_id_from_type("driver-" <> rest), do: rest
  defp driver_id_from_type(type_id), do: type_id

  defp latlng(position) do
    [lat, lng] = String.split(position, ",", parts: 2)
    %{lat: String.to_float(lat), lng: String.to_float(lng)}
  end

  defp shift_start, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp api_key, do: Application.get_env(:edenflowers, :here_api_key)
end
