defmodule Edenflowers.TourPlanning.FakeTest do
  use ExUnit.Case, async: true

  alias Edenflowers.TourPlanning.Fake

  @problem %{
    stops: [
      %{id: "order-1", position: "63.1157,21.61864", handling_seconds: 120},
      %{id: "order-2", position: "63.03232,21.54662", handling_seconds: 300},
      %{id: "order-3", position: "63.095,21.61", handling_seconds: 180}
    ],
    drivers: [%{id: "driver-b"}, %{id: "driver-a"}]
  }

  test "returns stable multi-route fixtures without calculating geography" do
    assert {:ok, [first_route, second_route] = routes} = Fake.solve(@problem)
    assert Fake.solve(@problem) == {:ok, routes}

    assert first_route.driver_id == "driver-a"
    assert Enum.map(first_route.stops, & &1.stop_id) == ["order-1", "order-3"]
    assert Enum.map(first_route.stops, & &1.sequence) == [1, 2]
    assert first_route.total_distance_m == 4_000
    assert first_route.total_driving_s == 600
    assert first_route.total_duration_s == 900

    assert second_route.driver_id == "driver-b"
    assert Enum.map(second_route.stops, & &1.stop_id) == ["order-2"]
    assert second_route.total_distance_m == 2_000
    assert second_route.total_driving_s == 300
    assert second_route.total_duration_s == 600
  end

  test "returns unassigned when stops exist without an available driver" do
    assert {:error, :unassigned} = Fake.solve(%{@problem | drivers: []})
  end

  test "returns an empty solution when there are no stops" do
    assert {:ok, []} = Fake.solve(%{@problem | stops: [], drivers: []})
  end
end
