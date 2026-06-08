defmodule Edenflowers.Geography.TourPlanning.Fake do
  @moduledoc """
  Deterministic tour-planning fake for tests.

  Stops retain their input order and are distributed across the available
  drivers. Fixed leg metrics keep assertions stable while handling time still
  contributes to each route's total duration.
  """

  @behaviour Edenflowers.Geography.TourPlanning.Behaviour

  @leg_distance_m 2_000
  @leg_duration_s 300

  @impl true
  def solve(%{stops: [], drivers: _drivers}), do: {:ok, []}
  def solve(%{stops: [_ | _], drivers: []}), do: {:error, :unassigned}

  def solve(%{stops: stops, drivers: drivers}) do
    drivers = Enum.sort_by(drivers, &to_string(&1.id))

    routes =
      stops
      |> Enum.with_index()
      |> Enum.group_by(fn {_stop, index} -> rem(index, length(drivers)) end, &elem(&1, 0))
      |> Enum.sort()
      |> Enum.map(fn {driver_index, assigned_stops} ->
        build_route(Enum.at(drivers, driver_index), assigned_stops)
      end)

    {:ok, routes}
  end

  defp build_route(driver, stops) do
    solved_stops =
      stops
      |> Enum.with_index(1)
      |> Enum.map(fn {stop, sequence} ->
        %{
          stop_id: stop.id,
          sequence: sequence,
          leg_from_previous: %{
            distance_m: @leg_distance_m,
            duration_s: @leg_duration_s
          }
        }
      end)

    total_driving_s = length(stops) * @leg_duration_s
    handling_s = Enum.sum(Enum.map(stops, & &1.handling_seconds))

    %{
      driver_id: driver.id,
      stops: solved_stops,
      total_distance_m: length(stops) * @leg_distance_m,
      total_driving_s: total_driving_s,
      total_duration_s: total_driving_s + handling_s
    }
  end
end
