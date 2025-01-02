defmodule Edenflowers.HereAPI do
  require Logger

  @origin "63.1243488,21.5974075"
  @get_coordinates_error {:error, "HereAPI: could not get coordinates"}
  @get_distance_error {:error, "HereAPI: could not get distance"}

  def complete_address(query) do
    url =
      "https://autocomplete.search.hereapi.com/v1/autocomplete?q=#{URI.encode(query)}&at=#{@origin}&limit=1&apiKey=#{api_key()}"

    with {:ok, %{body: body}} <- Req.get(url),
         %{"items" => [%{"address" => %{"city" => city, "postalCode" => postal_code}} | _]} <- body do
      %{query: query, city: city, postal_code: postal_code}
    else
      err ->
        Logger.error(err)
        {:error, "HereAPI: could not complete address"}
    end
  end

  @spec get_coordinates(binary()) :: {:ok, {number(), number()}} | {:error, binary()}
  def get_coordinates(address) do
    url =
      "https://geocode.search.hereapi.com/v1/geocode?q=#{URI.encode(address)}&at=#{@origin}&limit=1&apiKey=#{api_key()}"

    with {:ok, %{body: body}} <- Req.get(url),
         %{"items" => [%{"position" => %{"lat" => lat, "lng" => lng}} | _]} <- body do
      {:ok, {lat, lng}}
    else
      err ->
        Logger.error(err)
        @get_coordinates_error
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
      err ->
        Logger.error(err)
        @get_distance_error
    end
  end

  def get_distance({:error, _}), do: @get_distance_error

  defp api_key, do: Application.get_env(:edenflowers, :here_api_key)
end
