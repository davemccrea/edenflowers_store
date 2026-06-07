defmodule Edenflowers.TourPlanning.SolverTest do
  use ExUnit.Case, async: false

  alias Edenflowers.TourPlanning.Solver

  defmodule ConfiguredFake do
    @behaviour Edenflowers.TourPlanning.Behaviour

    @impl true
    def solve(_problem), do: {:error, :configured_fake}
  end

  test "delegates to the configured implementation" do
    previous = Application.get_env(:edenflowers, :tour_planning)

    on_exit(fn ->
      if previous do
        Application.put_env(:edenflowers, :tour_planning, previous)
      else
        Application.delete_env(:edenflowers, :tour_planning)
      end
    end)

    Application.put_env(:edenflowers, :tour_planning, ConfiguredFake)

    assert Solver.solve(%{stops: [], drivers: []}) == {:error, :configured_fake}
  end
end
