defmodule Edenflowers.TourPlanning.Solver do
  @moduledoc """
  Resolves the configured tour-planning implementation.

  Production and development default to the HERE adapter. Tests configure the
  deterministic fake.
  """

  @spec solve(Edenflowers.TourPlanning.Behaviour.problem()) ::
          {:ok, [Edenflowers.TourPlanning.Behaviour.solved_route()]}
          | {:error, atom()}
  def solve(problem) do
    implementation().solve(problem)
  end

  defp implementation do
    Application.get_env(:edenflowers, :tour_planning, Edenflowers.TourPlanning)
  end
end
