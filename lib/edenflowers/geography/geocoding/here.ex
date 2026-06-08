defmodule Edenflowers.Geography.Geocoding.HERE do
  @moduledoc """
  HERE Geocoding Search API adapter.

  Resolves a free-text address into a structured address, a `"lat,lng"` position
  string, and a HERE place id. The geocoding is centred on the shop's location
  so the search returns Vaasa-area results first.
  """

  @behaviour Edenflowers.Geography.Geocoding.Behaviour

  require Logger

  @origin "63.1243488,21.5974075"

  @impl true
  def get_address(query, locale) when is_binary(query) and is_binary(locale) do
    url =
      "https://geocode.search.hereapi.com/v1/geocode?q=#{URI.encode(query)}&at=#{@origin}&limit=1&lang=#{language(locale)}&apiKey=#{api_key()}"

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
             }
             | _
           ]
         } <- body do
      address = "#{street} #{house_number}, #{postal_code} #{city}"
      position = "#{lat},#{lng}"

      {:ok, {address, position, here_id}}
    else
      {:ok, %{status: status}} ->
        Logger.error("Geocoding returned status #{status}")
        {:error, :address_not_found}

      _ ->
        {:error, :address_not_found}
    end
  end

  defp language("fi"), do: "fi"
  defp language("sv-FI"), do: "sv"
  defp language("en-GB"), do: "en"
  defp language(locale), do: locale |> String.split("-", parts: 2) |> hd()

  defp api_key, do: Application.get_env(:edenflowers, :here_api_key)
end
