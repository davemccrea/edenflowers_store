defmodule Edenflowers.Store.HereAPI do
  @origin "63.1243488,21.5974075"

  @spec get_coordinates(binary()) :: {:ok, {number(), number()}} | {:error, binary()}
  def get_coordinates(address) do
    url =
      "https://geocode.search.hereapi.com/v1/geocode?q=#{URI.encode(address)}&at=#{@origin}&limit=1&apiKey=#{api_key()}"

    with {:ok, %{body: body}} <- Req.get(url),
         %{"items" => [%{"position" => %{"lat" => lat, "lng" => lng}} | _]} <- body do
      {:ok, {lat, lng}}
    else
      _ -> {:error, "HereAPI: could not get coordinates"}
    end
  end

  @spec get_distance({:ok, {number(), number()}}) :: {:ok, number()} | {:error, binary()}
  def get_distance({:ok, {lat, lng}}) when is_number(lat) and is_number(lng) do
    destination = "#{lat},#{lng}"

    url =
      "https://router.hereapi.com/v8/routes?transportMode=car&origin=#{@origin}&destination=#{destination}&return=summary&apikey=#{api_key()}"

    with {:ok, %{body: body}} <- Req.get(url),
         %{"routes" => [%{"sections" => [%{"summary" => %{"length" => length}} | _]} | _]} <- body do
      {:ok, length}
    else
      _ -> {:error, "HereAPI: could not get distance"}
    end
  end

  def get_distance({:error, _}), do: {:error, "HereAPI: could not get distance"}

  defp api_key, do: Application.get_env(:edenflowers, :here_api_key)
end
