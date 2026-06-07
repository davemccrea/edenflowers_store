defmodule Edenflowers.HereTourPlanning.Input do
  @moduledoc """
  Domain-oriented input to the optimizer.

  `orders` and `shop` carry numeric coordinates (the caller parses the order's
  stored `"lat,lng"` position). `vehicle_ids` is one id per selected driver; the
  optimizer treats them as equivalent cars starting at the shop. `date` is the
  delivery date in `Europe/Helsinki`, used to anchor the nominal shift.
  """
  @enforce_keys [:orders, :vehicle_ids, :shop, :date]
  defstruct [
    :orders,
    :vehicle_ids,
    :shop,
    :date,
    service_duration: 300,
    shift_start: ~T[08:00:00],
    shift_end: ~T[23:59:00]
  ]

  @type coord :: %{lat: float(), lng: float()}
  @type t :: %__MODULE__{
          orders: [%{id: String.t(), lat: float(), lng: float()}],
          vehicle_ids: [String.t()],
          shop: coord(),
          date: Date.t(),
          service_duration: non_neg_integer(),
          shift_start: Time.t(),
          shift_end: Time.t()
        }
end

defmodule Edenflowers.HereTourPlanning.Stop do
  @moduledoc "One ordered delivery within an optimized assignment. Distances in metres, durations in seconds."
  @enforce_keys [:order_id, :sequence, :leg_distance, :leg_duration]
  defstruct [:order_id, :sequence, :leg_distance, :leg_duration]
end

defmodule Edenflowers.HereTourPlanning.Assignment do
  @moduledoc "The ordered stops and totals assigned to one vehicle/driver."
  @enforce_keys [:vehicle_id, :stops, :total_distance, :total_driving_duration, :total_service_duration]
  defstruct [:vehicle_id, :stops, :total_distance, :total_driving_duration, :total_service_duration]
end

defmodule Edenflowers.HereTourPlanning.Plan do
  @moduledoc "A parsed optimization result: one assignment per vehicle that received orders."
  @enforce_keys [:assignments]
  defstruct [:assignments]
end

defmodule Edenflowers.HereTourPlanning.Behaviour do
  alias Edenflowers.HereTourPlanning.{Input, Plan}

  @callback optimize(Input.t()) :: {:ok, Plan.t()} | {:error, term()}
end

defmodule Edenflowers.HereTourPlanning do
  @moduledoc """
  Adapter for HERE Tour Planning v3.

  Separate from `Edenflowers.HereAPI` (geocoding/routing). Builds a problem with
  one equivalent car per selected driver and an open-ended shift starting at the
  shop, asks HERE to assign and order all deliveries minimizing the longest route
  first and total cost second, and parses the result into a stable internal
  `Plan`. Any unassigned, duplicate, missing, or unknown job is rejected — there
  is no fallback.
  """
  @behaviour Edenflowers.HereTourPlanning.Behaviour

  require Logger

  alias Edenflowers.HereTourPlanning.{Assignment, Input, Plan, Stop}

  @endpoint "https://tourplanning.hereapi.com/v3/problems"

  @impl true
  def optimize(%Input{} = input) do
    problem = build_problem(input)

    started = System.monotonic_time()

    result =
      with {:ok, %{status: 200, body: body}} <- post_problem(problem),
           {:ok, plan} <- parse_plan(body, input) do
        {:ok, plan}
      else
        {:ok, %{status: status, body: body}} ->
          # The body is a schema/validation error, not customer data — safe to log.
          Logger.error("HERE Tour Planning returned status #{status}: #{inspect(body)}")
          {:error, {:here_status, status}}

        {:error, reason} ->
          {:error, reason}
      end

    duration_ms = System.convert_time_unit(System.monotonic_time() - started, :native, :millisecond)

    Logger.info(
      "HERE Tour Planning optimize: vehicles=#{length(input.vehicle_ids)} " <>
        "orders=#{length(input.orders)} duration_ms=#{duration_ms} outcome=#{elem(result, 0)}"
    )

    result
  end

  defp post_problem(problem) do
    Req.post(@endpoint, params: [apiKey: api_key()], json: problem)
  end

  @doc """
  Builds the HERE v3 problem payload from domain input. Public so contract tests
  can assert the request shape without performing HTTP.
  """
  def build_problem(%Input{} = input) do
    %{
      fleet: %{
        types: Enum.map(input.vehicle_ids, &vehicle_type(&1, input)),
        profiles: [%{type: "car", name: "car"}]
      },
      plan: %{
        jobs: Enum.map(input.orders, &delivery_job(&1, input))
      },
      # Objective type names are camelCase in the v3 schema. Keep every order
      # assigned (so the parser can reject leftovers), then minimize the longest
      # tour's duration (balanced completion time), then total cost (travel time).
      objectives: [
        %{type: "minimizeUnassigned"},
        %{type: "minimizeDuration"},
        %{type: "minimizeCost"}
      ]
    }
  end

  defp vehicle_type(vehicle_id, input) do
    %{
      id: to_string(vehicle_id),
      profile: "car",
      costs: %{fixed: 0.0, distance: 0.0001, time: 0.001},
      shifts: [
        %{
          start: %{
            time: shift_time(input.date, input.shift_start),
            location: %{lat: input.shop.lat, lng: input.shop.lng}
          },
          end: %{
            time: shift_time(input.date, input.shift_end),
            location: %{lat: input.shop.lat, lng: input.shop.lng}
          }
        }
      ],
      capacity: [length(input.orders)],
      amount: 1
    }
  end

  defp delivery_job(order, input) do
    %{
      id: to_string(order.id),
      tasks: %{
        deliveries: [
          %{
            places: [
              %{
                location: %{lat: order.lat, lng: order.lng},
                duration: input.service_duration
              }
            ],
            demand: [1]
          }
        ]
      }
    }
  end

  defp shift_time(date, time) do
    date
    |> DateTime.new!(time, "Europe/Helsinki")
    |> DateTime.to_iso8601()
  end

  @doc """
  Parses a HERE v3 response into a `Plan`, validating that every input order is
  assigned exactly once to a known vehicle. Public so contract tests can drive it
  with recorded fixtures.
  """
  def parse_plan(body, %Input{} = input) do
    expected_ids = MapSet.new(input.orders, &to_string(&1.id))
    known_vehicles = MapSet.new(input.vehicle_ids, &to_string/1)

    with :ok <- reject_unassigned(body),
         {:ok, assignments} <- parse_tours(body, known_vehicles, input),
         :ok <- verify_all_assigned(assignments, expected_ids) do
      {:ok, %Plan{assignments: assignments}}
    end
  end

  defp reject_unassigned(%{"unassigned" => [_ | _] = unassigned}) do
    {:error, {:unassigned, Enum.map(unassigned, & &1["jobId"])}}
  end

  defp reject_unassigned(_), do: :ok

  defp parse_tours(%{"tours" => tours}, known_vehicles, input) when is_list(tours) do
    Enum.reduce_while(tours, {:ok, []}, fn tour, {:ok, acc} ->
      case parse_tour(tour, known_vehicles, input) do
        {:ok, assignment} -> {:cont, {:ok, [assignment | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, assignments} -> {:ok, Enum.reverse(assignments)}
      error -> error
    end
  end

  defp parse_tours(_, _, _), do: {:error, :malformed_response}

  defp parse_tour(tour, known_vehicles, input) do
    vehicle_id = vehicle_id_from_tour(tour)

    if MapSet.member?(known_vehicles, vehicle_id) do
      stops = Map.get(tour, "stops", [])
      {delivery_stops, _} = build_stops(stops, input.service_duration)

      total_distance = total_distance(stops)
      driving = Enum.reduce(delivery_stops, 0, &(&1.leg_duration + &2))
      service = length(delivery_stops) * input.service_duration

      {:ok,
       %Assignment{
         vehicle_id: vehicle_id,
         stops: delivery_stops,
         total_distance: total_distance,
         total_driving_duration: driving,
         total_service_duration: service
       }}
    else
      {:error, {:unknown_vehicle, vehicle_id}}
    end
  end

  # HERE forms the response vehicleId as "<typeId>_<n>". Driver ids are UUIDs and
  # never contain "_", so trimming the trailing index recovers the typeId.
  defp vehicle_id_from_tour(%{"typeId" => type_id}), do: type_id

  defp vehicle_id_from_tour(%{"vehicleId" => vehicle_id}) do
    vehicle_id |> String.split("_") |> Enum.drop(-1) |> Enum.join("_")
  end

  # Walks the stops, computing each delivery's leg from the preceding stop (the
  # shop for the first delivery). Cumulative `distance` is metres from the start.
  defp build_stops(stops, _service_duration) do
    Enum.reduce(stops, {[], nil}, fn stop, {acc, prev} ->
      case delivery_job_id(stop) do
        nil ->
          {acc, stop}

        job_id ->
          leg_distance = stop_distance(stop) - stop_distance(prev)
          leg_duration = leg_seconds(prev, stop)
          sequence = length(acc) + 1

          entry = %Stop{
            order_id: job_id,
            sequence: sequence,
            leg_distance: leg_distance,
            leg_duration: leg_duration
          }

          {acc ++ [entry], stop}
      end
    end)
  end

  defp delivery_job_id(%{"activities" => activities}) do
    Enum.find_value(activities, fn
      %{"type" => "delivery", "jobId" => job_id} -> job_id
      _ -> nil
    end)
  end

  defp delivery_job_id(_), do: nil

  defp stop_distance(nil), do: 0
  defp stop_distance(%{"distance" => distance}), do: distance
  defp stop_distance(_), do: 0

  defp total_distance(stops) do
    stops
    |> Enum.map(&stop_distance/1)
    |> Enum.max(fn -> 0 end)
  end

  defp leg_seconds(prev, stop) do
    with %{"time" => %{"departure" => departure}} <- prev,
         %{"time" => %{"arrival" => arrival}} <- stop,
         {:ok, dep, _} <- DateTime.from_iso8601(departure),
         {:ok, arr, _} <- DateTime.from_iso8601(arrival) do
      max(DateTime.diff(arr, dep, :second), 0)
    else
      _ -> 0
    end
  end

  defp verify_all_assigned(assignments, expected_ids) do
    assigned_ids =
      assignments
      |> Enum.flat_map(fn a -> Enum.map(a.stops, & &1.order_id) end)

    cond do
      length(assigned_ids) != length(Enum.uniq(assigned_ids)) ->
        {:error, :duplicate_assignment}

      MapSet.new(assigned_ids) != expected_ids ->
        {:error, :missing_assignment}

      true ->
        :ok
    end
  end

  defp api_key, do: Application.get_env(:edenflowers, :here_api_key)
end
