defmodule Edenflowers.Geography.Routing.Behaviour do
  @callback distance(origin :: String.t(), destination :: String.t()) ::
              {:ok, integer()} | {:error, atom()}
end

defmodule Edenflowers.Geography.Routing do
  @moduledoc """
  Entry point for routing distance calculations.

  Production and development default to the HERE adapter. Tests configure a
  Mox mock (see `Edenflowers.Geography.Routing.Mock`).
  """

  @spec distance(String.t(), String.t()) :: {:ok, integer()} | {:error, atom()}
  def distance(origin, destination) do
    implementation().distance(origin, destination)
  end

  defp implementation do
    Application.get_env(:edenflowers, :routing, Edenflowers.Geography.Routing.HERE)
  end
end
