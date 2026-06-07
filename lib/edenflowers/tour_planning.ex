defmodule Edenflowers.TourPlanning.Behaviour do
  @moduledoc """
  The optimizer boundary for delivery dispatch.

  A `problem` is the set of delivery stops to place and the drivers available to
  place them across. The solver assigns every stop to a driver and sequences each
  driver's stops, returning per-driver ordered routes with per-leg and total
  distance/duration. Drivers are equivalent in v1 (no capacity, no time windows);
  every route starts at the shop and ends at its last delivery.

  Returns `{:error, :unassigned}` when not every stop can be placed — planning is
  then blocked, there is no partial result.
  """

  @typedoc "A delivery stop. `position` is a HERE `\"lat,lng\"` string (as snapshotted on the order)."
  @type stop_input :: %{
          id: String.t(),
          position: String.t(),
          handling_seconds: non_neg_integer()
        }

  @type driver_input :: %{id: String.t()}

  @type problem :: %{stops: [stop_input()], drivers: [driver_input()]}

  @typedoc "Distance (metres) and driving time (seconds) for a single leg between two points."
  @type leg :: %{distance_m: non_neg_integer(), duration_s: non_neg_integer()}

  @type solved_stop :: %{
          stop_id: String.t(),
          sequence: pos_integer(),
          leg_from_previous: leg()
        }

  @typedoc """
  One driver's route. `total_driving_s` is driving only; `total_duration_s` adds the
  per-stop handling time (driving + Σ handling), which is what the review screen shows.
  """
  @type solved_route :: %{
          driver_id: String.t(),
          stops: [solved_stop()],
          total_distance_m: non_neg_integer(),
          total_driving_s: non_neg_integer(),
          total_duration_s: non_neg_integer()
        }

  @callback solve(problem()) :: {:ok, [solved_route()]} | {:error, :unassigned | atom()}
end

defmodule Edenflowers.TourPlanning do
  @moduledoc """
  HERE Tour Planning adapter (synchronous `/v3/problems` endpoint).

  Maps each driver to a vehicle whose shift starts at the shop with no end location
  (open route), and each stop to a delivery job carrying its handling time.

  The goal is to minimise **total driving distance** (the cheapest plan). The objectives
  are `minimizeUnassigned -> minimizeCost` with cost weighted purely to distance, so HERE
  places every order and then minimises kilometres driven.

  Because routes are open (no return to the shop), distance genuinely varies with how the
  stops cluster: HERE uses more of the available drivers only when splitting clusters
  actually saves driving, and consolidates otherwise. So the number of drivers used falls
  out of the geometry — we need no balancing logic or driver-count dial. Selected drivers
  are an available *pool* (the upper bound); unused drivers simply get no route.
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
  def solve(%{stops: _stops, drivers: _drivers} = problem_input) do
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
  def build_problem(%{stops: stops, drivers: drivers}) do
    %{
      fleet: %{
        types: Enum.map(drivers, &vehicle_type/1),
        profiles: [%{name: @profile, type: "car"}]
      },
      plan: %{jobs: Enum.map(stops, &job/1)},
      # Place every order, then minimise cost — which we weight purely to distance, so
      # this is "least driving". HERE chooses how many drivers that takes.
      objectives: [
        %{type: "minimizeUnassigned"},
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
  def parse_solution(body, %{stops: stops, drivers: drivers}) do
    case body do
      %{"unassigned" => [_ | _]} -> {:error, :unassigned}
      _ -> parse_tours(body, stops, drivers)
    end
  end

  # Translate HERE tours into the behaviour's output. Each tour's first stop is the
  # shop departure (no job activity); delivery stops carry a cumulative distance from
  # the start, so per-leg distance is the diff between consecutive stops.
  defp parse_tours(%{"tours" => tours}, stops, drivers) do
    handling_by_id = Map.new(stops, fn s -> {s.id, s.handling_seconds} end)

    routes =
      Enum.map(tours, fn tour ->
        driver_id = driver_id_from_type(tour["typeId"], drivers)
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

    {:ok, routes}
  end

  defp parse_tours(_body, _stops, _drivers), do: {:error, :tour_planning_failed}

  # Walk the tour's stops in order, threading the previous stop so each delivery's leg
  # is measured from whatever came before it (the shop departure for the first). HERE
  # reports a cumulative distance per stop, so a leg's distance is the diff; a leg's
  # driving time is this stop's arrival minus the previous stop's departure.
  defp solved_stops(here_stops) do
    {solved, _prev} =
      Enum.reduce(here_stops, {[], nil}, fn here_stop, {acc, prev} ->
        case delivery_job_id(here_stop) do
          nil ->
            {acc, here_stop}

          job_id ->
            leg = %{
              distance_m: max(cumulative_distance(here_stop) - cumulative_distance(prev), 0),
              duration_s: leg_seconds(prev, here_stop)
            }

            {[{job_id, leg} | acc], here_stop}
        end
      end)

    solved
    |> Enum.reverse()
    |> Enum.with_index(1)
    |> Enum.map(fn {{job_id, leg}, sequence} ->
      %{stop_id: job_id, sequence: sequence, leg_from_previous: leg}
    end)
  end

  defp delivery_job_id(%{"activities" => activities}) do
    Enum.find_value(activities, fn
      %{"type" => "delivery", "jobId" => job_id} -> job_id
      _ -> nil
    end)
  end

  defp delivery_job_id(_), do: nil

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

  defp driver_id_from_type("driver-" <> rest, _drivers), do: rest
  defp driver_id_from_type(type_id, _drivers), do: type_id

  defp latlng(position) do
    [lat, lng] = String.split(position, ",", parts: 2)
    %{lat: String.to_float(lat), lng: String.to_float(lng)}
  end

  defp shift_start, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp api_key, do: Application.get_env(:edenflowers, :here_api_key)
end
