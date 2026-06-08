defmodule Edenflowers.Geography.Routing.HERE do
  @moduledoc """
  HERE Routing API adapter.

  Calculates the driving distance (in metres) between an origin and a
  destination, both expressed as `"lat,lng"` strings.
  """

  @behaviour Edenflowers.Geography.Routing.Behaviour

  require Logger

  @impl true
  def distance(origin, destination) when is_binary(origin) and is_binary(destination) do
    url =
      "https://router.hereapi.com/v8/routes?transportMode=car&origin=#{origin}&destination=#{destination}&return=summary&apikey=#{api_key()}"

    with {:ok, %{status: 200, body: body}} <- Req.get(url),
         {:ok, total_length} <- sum_route_lengths(body) do
      {:ok, total_length}
    else
      _ ->
        {:error, :distance_not_calculated}
    end
  end

  defp sum_route_lengths(%{"routes" => []}), do: {:error, 0}

  defp sum_route_lengths(%{"routes" => routes}) do
    total_length =
      routes
      |> Enum.flat_map(& &1["sections"])
      |> Enum.map(&get_in(&1, ["summary", "length"]))
      |> Enum.sum()

    {:ok, total_length}
  end

  defp api_key, do: Application.get_env(:edenflowers, :here_api_key)
end
