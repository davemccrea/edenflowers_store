defmodule Edenflowers.External.WeatherAPI do
  @moduledoc """
  Reads the outside temperature at the shop from MET Norway's forecast, so Jennie
  knows how warmly to pack flowers.
  """

  alias Edenflowers.ShopTime

  # The shop, to the four decimals MET Norway allows.
  @url "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=63.1244&lon=21.5974"

  # MET Norway's terms require a User-Agent that identifies the caller.
  @user_agent "edenflowers.fi info@edenflowers.fi"

  # MET Norway's symbol codes, such as "lightrainshowersandthunder_day", grouped
  # by what matters for packing. Order matters: the first match wins.
  @conditions [
    {"thunder", :thunder},
    {"sleet", :sleet},
    {"snow", :snow},
    {"rain", :rain},
    {"fog", :fog},
    {"partlycloudy", :partly_cloudy},
    {"fair", :partly_cloudy},
    {"cloudy", :cloudy}
  ]

  @cache_minutes 30

  @doc """
  The forecast last read by `today/1`, while it is under half an hour old and
  from the shop's same day. Asks nobody, so a page can show it at once.
  """
  def cached(now \\ DateTime.utc_now()) do
    with {weather, read_at} <- :persistent_term.get(__MODULE__, nil),
         true <- DateTime.diff(now, read_at, :minute) in 0..(@cache_minutes - 1),
         true <- ShopTime.today(read_at) == ShopTime.today(now) do
      weather
    else
      _ -> nil
    end
  end

  @doc """
  Reads the highest and lowest temperature in whole °C and the conditions for
  what is left of the shop's day, and keeps them for `cached/1`. The forecast
  starts at the current hour, so hours already past aren't counted.
  """
  def today(now \\ DateTime.utc_now()) do
    today = ShopTime.today(now)

    with {:ok, %{status: 200, body: %{"properties" => %{"timeseries" => timeseries}}}} <-
           Req.get([url: @url, user_agent: @user_agent, receive_timeout: 5_000] ++ req_options()),
         [%{"data" => next} | _] = hours <- Enum.filter(timeseries, &(shop_date(&1["time"]) == today)) do
      temperatures = Enum.map(hours, & &1["data"]["instant"]["details"]["air_temperature"])

      symbol =
        get_in(next, ["next_6_hours", "summary", "symbol_code"]) || next["next_1_hours"]["summary"]["symbol_code"]

      weather = %{
        high: round(Enum.max(temperatures)),
        low: round(Enum.min(temperatures)),
        condition: condition(symbol),
        night?: String.ends_with?(symbol, "_night")
      }

      :persistent_term.put(__MODULE__, {weather, now})
      {:ok, weather}
    else
      _ -> :error
    end
  end

  defp shop_date(time) do
    {:ok, time, 0} = DateTime.from_iso8601(time)
    ShopTime.today(time)
  end

  defp condition(symbol) do
    Enum.find_value(@conditions, :clear, fn {part, condition} -> symbol =~ part && condition end)
  end

  defp req_options, do: Application.get_env(:edenflowers, :weather_req_options, [])
end
