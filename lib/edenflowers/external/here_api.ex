defmodule Edenflowers.External.HereAPI.Behaviour do
  @moduledoc """
  Contract for geocoding and route-distance clients, allowing deterministic replacements in tests.
  """

  @callback geocode(query :: String.t()) ::
              {:ok, {String.t(), String.t(), String.t()}} | {:error, atom()}
  @callback route_distance(position :: String.t()) :: {:ok, integer()} | {:error, atom()}
  @callback sequence(start :: String.t(), stops :: [map()], finish :: String.t(), departure :: DateTime.t()) ::
              {:ok, map()} | {:error, atom()}
end

defmodule Edenflowers.External.HereAPI do
  @moduledoc """
  Geocodes delivery addresses and obtains driving distance through HERE Maps for delivery pricing.
  """

  @behaviour Edenflowers.External.HereAPI.Behaviour

  use GettextSigils, backend: EdenflowersWeb.Gettext

  require Logger

  @origin "63.1243488,21.5974075"

  @doc "The configured implementation: this module, or the mock in tests."
  def impl, do: Application.get_env(:edenflowers, :here_api, __MODULE__)

  @doc "The shop's coordinates, \"latitude,longitude\", where deliveries are measured from."
  def shop_position, do: @origin

  def geocode(query) when is_binary(query) do
    url =
      "https://geocode.search.hereapi.com/v1/geocode?q=#{URI.encode(query)}&at=#{@origin}&limit=1&lang=#{Gettext.get_locale(EdenflowersWeb.Gettext)}&apiKey=#{api_key()}"

    with {:ok, %{status: 200, body: body}} <- Req.get(url),
         %{
           "items" => [
             %{
               "address" => %{
                 "street" => street,
                 "houseNumber" => house_number,
                 "postalCode" => postal_code,
                 "city" => city
               },
               "id" => here_id,
               "position" => %{"lat" => lat, "lng" => lng}
             } = _head
             | _tail
           ]
         } <- body do
      address = "#{street} #{house_number}, #{postal_code} #{city}"
      position = "#{lat},#{lng}"

      {:ok, {address, position, here_id}}
    else
      {:ok, %{status: status}} ->
        Logger.error("HereAPI geocode returned status #{status}")
        {:error, :address_not_found}

      _ ->
        {:error, :address_not_found}
    end
  end

  def route_distance(position) when is_binary(position) do
    url =
      "https://router.hereapi.com/v8/routes?transportMode=car&origin=#{@origin}&destination=#{position}&return=summary&apikey=#{api_key()}"

    with {:ok, %{body: body}} <- Req.get(url),
         {:ok, total_length} <- sum_route_lengths(body) do
      {:ok, total_length}
    else
      _ -> {:error, :distance_not_calculated}
    end
  end

  @doc """
  Orders the stops into the fastest drive from `start` to `finish`, leaving at
  `departure`. Each stop is `%{id:, position:, service:}` (seconds spent there)
  and an optional `window: {from, to}` of DateTimes it must be reached in.
  Returns the stops' ids in driving order with when each one's visit starts,
  which is after any wait for its window to open.
  """
  def sequence(start, stops, finish, departure) do
    destinations =
      stops
      |> Enum.with_index(1)
      |> Enum.map(fn {stop, n} -> {"destination#{n}", destination(stop)} end)

    params =
      [start: "start;#{start}", end: "end;#{finish}"] ++
        destinations ++
        [
          mode: "fastest;car;traffic:enabled",
          improveFor: "time",
          departure: DateTime.to_iso8601(departure),
          apiKey: api_key()
        ]

    service = Map.new(stops, &{&1.id, &1.service})

    with {:ok, %{status: 200, body: %{"results" => [result | _]}}} <-
           Req.get("https://wps.hereapi.com/v8/findsequence2", params: params),
         {:ok, route} <- parse_sequence(result, service) do
      {:ok, route}
    else
      {:ok, %{status: status, body: body}} ->
        Logger.error("HereAPI sequence returned status #{status}: #{inspect(body["errors"] || body)}")
        {:error, :route_not_planned}

      other ->
        Logger.error("HereAPI sequence failed: #{inspect(other, limit: 5)}")
        {:error, :route_not_planned}
    end
  end

  defp destination(%{id: id, position: position, service: service} = stop) do
    window =
      case stop[:window] do
        {from, to} -> ";acc:#{weekday_time(from)}|#{weekday_time(to)}"
        nil -> ""
      end

    "#{id};#{position}#{window};st:#{service}"
  end

  # HERE's windows repeat weekly, as "fr10:00:00+02:00".
  defp weekday_time(datetime) do
    day = Enum.at(~w(mo tu we th fr sa su), Date.day_of_week(datetime) - 1)
    iso = DateTime.to_iso8601(%{datetime | microsecond: {0, 0}})
    day <> String.slice(iso, 11..-1//1)
  end

  @doc false
  def parse_sequence(%{"waypoints" => waypoints, "distance" => distance, "timeBreakdown" => breakdown}, service) do
    ordered = Enum.sort_by(waypoints, & &1["sequence"])
    {stops, [finish]} = ordered |> Enum.drop(1) |> Enum.split(-1)

    with {:ok, back_at, _} <- DateTime.from_iso8601(finish["estimatedArrival"]) do
      {:ok,
       %{
         stops:
           Enum.map(stops, fn %{"id" => id, "estimatedDeparture" => leaves} ->
             {:ok, leaves_at, _} = DateTime.from_iso8601(leaves)
             %{id: id, starts_at: DateTime.add(leaves_at, -Map.fetch!(service, id))}
           end),
         back_at: back_at,
         distance: String.to_integer(distance),
         driving: breakdown["driving"]
       }}
    end
  end

  def parse_sequence(_result, _service), do: {:error, :unexpected_response}

  def sum_route_lengths(%{"routes" => []}), do: {:error, :no_routes}

  def sum_route_lengths(%{"routes" => routes}) do
    total_length =
      routes
      |> Enum.flat_map(& &1["sections"])
      |> Enum.map(&get_in(&1, ["summary", "length"]))
      |> Enum.sum()

    {:ok, total_length}
  end

  defp api_key, do: Application.get_env(:edenflowers, :here_api_key)
end
