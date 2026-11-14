defmodule Edenflowers.External.HereAPISequenceTest do
  use ExUnit.Case, async: true

  alias Edenflowers.External.HereAPI

  # Recorded from HERE's findsequence2: b first, then a, which waits for its 10:00 window.
  @result %{
    "waypoints" => [
      %{
        "id" => "start",
        "sequence" => 0,
        "estimatedArrival" => nil,
        "estimatedDeparture" => "2026-11-20T09:00:00+02:00"
      },
      %{
        "id" => "a",
        "sequence" => 2,
        "estimatedArrival" => "2026-11-20T09:25:50+02:00",
        "estimatedDeparture" => "2026-11-20T10:05:00+02:00"
      },
      %{
        "id" => "b",
        "sequence" => 1,
        "estimatedArrival" => "2026-11-20T09:12:54+02:00",
        "estimatedDeparture" => "2026-11-20T09:17:54+02:00"
      },
      %{"id" => "end", "sequence" => 3, "estimatedArrival" => "2026-11-20T10:13:58+02:00", "estimatedDeparture" => nil}
    ],
    "distance" => "14905",
    "time" => "4438",
    "timeBreakdown" => %{"driving" => 1788, "service" => 600, "rest" => 0, "waiting" => 2050, "break" => 0}
  }

  test "orders the stops by HERE's sequence and starts each visit after any wait for its window" do
    assert {:ok, route} = HereAPI.parse_sequence(@result, %{"a" => 300, "b" => 300})

    assert route.stops == [
             %{id: "b", starts_at: ~U[2026-11-20 07:12:54Z]},
             %{id: "a", starts_at: ~U[2026-11-20 08:00:00Z]}
           ]

    assert route.back_at == ~U[2026-11-20 08:13:58Z]
    assert route.distance == 14_905
    assert route.driving == 1788
  end

  test "sends a stop's window as HERE's weekday times, in the shop's offset on either side of summer time" do
    tz = Edenflowers.ShopTime.timezone()
    window = fn date, from, to -> {DateTime.new!(date, from, tz), DateTime.new!(date, to, tz)} end

    assert HereAPI.destination(%{id: "a", position: "63.1,21.6", service: 300, window: nil}) ==
             "a;63.1,21.6;st:300"

    assert HereAPI.destination(%{
             id: "a",
             position: "63.1,21.6",
             service: 300,
             window: window.(~D[2026-11-20], ~T[10:00:00], ~T[12:00:00])
           }) == "a;63.1,21.6;acc:fr10:00:00+02:00|fr12:00:00+02:00;st:300"

    assert HereAPI.destination(%{
             id: "a",
             position: "63.1,21.6",
             service: 300,
             window: window.(~D[2026-03-30], ~T[09:30:00], ~T[11:00:00])
           }) == "a;63.1,21.6;acc:mo09:30:00+03:00|mo11:00:00+03:00;st:300"
  end
end
