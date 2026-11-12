defmodule Edenflowers.External.WeatherAPITest do
  use ExUnit.Case, async: true

  alias Edenflowers.External.WeatherAPI

  defp hour(time, temperature, symbol) do
    %{
      "time" => time,
      "data" => %{
        "instant" => %{"details" => %{"air_temperature" => temperature}},
        "next_6_hours" => %{"summary" => %{"symbol_code" => symbol}}
      }
    }
  end

  test "reads the high, low and conditions for the rest of the shop's day" do
    Req.Test.stub(WeatherAPI, fn conn ->
      assert ["edenflowers.fi info@edenflowers.fi"] = Plug.Conn.get_req_header(conn, "user-agent")

      Req.Test.json(conn, %{
        "properties" => %{
          "timeseries" => [
            hour("2026-11-12T10:00:00Z", 2.6, "lightsnowshowers_day"),
            hour("2026-11-12T15:00:00Z", -1.4, "cloudy"),
            hour("2026-11-12T21:00:00Z", -3.5, "cloudy"),
            # Midnight in Helsinki: already tomorrow there, though still today in UTC.
            hour("2026-11-12T22:00:00Z", -9.0, "clearsky_night")
          ]
        }
      })
    end)

    weather = %{high: 3, low: -4, condition: :snow}
    assert {:ok, ^weather} = WeatherAPI.today(~U[2026-11-12 10:20:00Z])

    # Kept for half an hour, so the Overview shows it without asking again.
    assert WeatherAPI.cached(~U[2026-11-12 10:49:00Z]) == weather
    refute WeatherAPI.cached(~U[2026-11-12 10:50:00Z])
  end

  test "has no weather when the forecast can't be read" do
    Req.Test.stub(WeatherAPI, &Plug.Conn.send_resp(&1, 503, ""))

    assert :error = WeatherAPI.today()
  end
end
