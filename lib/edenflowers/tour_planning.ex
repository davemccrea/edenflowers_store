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

  @type optimization_strategy :: :cheapest | :balanced | :fastest

  @type problem :: %{
          optional(:strategy) => optimization_strategy(),
          stops: [stop_input()],
          drivers: [driver_input()]
        }

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
  Entry point for tour planning.

  Delegates to the configured adapter (default: `Edenflowers.TourPlanning.HERE`).
  Production and development use the HERE adapter. Tests configure the
  deterministic `Edenflowers.TourPlanning.Fake`.
  """

  @spec solve(Edenflowers.TourPlanning.Behaviour.problem()) ::
          {:ok, [Edenflowers.TourPlanning.Behaviour.solved_route()]}
          | {:error, atom()}
  def solve(problem) do
    implementation().solve(problem)
  end

  defp implementation do
    Application.get_env(:edenflowers, :tour_planning, Edenflowers.TourPlanning.HERE)
  end
end
