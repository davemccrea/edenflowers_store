defmodule Edenflowers.HereAPI do
  require Logger

  @origin "63.1243488,21.5974075"
  # TODO
  @lang "sv"

  def get_address(query) when is_binary(query) do
    url =
      "https://geocode.search.hereapi.com/v1/geocode?q=#{URI.encode(query)}&at=#{@origin}&limit=1&lang=#{@lang}&apiKey=#{api_key()}"

    with {:ok, %{body: body}} <- Req.get(url),
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
      _ ->
        {:error, :geocode}
    end
  end

  def get_distance(query) when is_binary(query) do
    url =
      "https://router.hereapi.com/v8/routes?transportMode=car&origin=#{@origin}&destination=#{query}&return=summary&apikey=#{api_key()}"

    with {:ok, %{body: body}} <- Req.get(url),
         %{"routes" => [%{"sections" => [%{"summary" => %{"length" => length}} | _]} | _]} <- body do
      {:ok, length}
    else
      _ -> {:error, :distance}
    end
  end

  defp api_key, do: Application.get_env(:edenflowers, :here_api_key)
end
