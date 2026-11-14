defmodule Edenflowers.Fulfillment.PlanRouteTest do
  use Edenflowers.DataCase, async: true

  import Generator
  import Mox

  alias Edenflowers.External.HereAPI
  alias Edenflowers.Fulfillment

  setup :verify_on_exit!

  @date ~D[2026-11-20]

  setup do
    {:ok, admin: generate(admin_user())}
  end

  defp delivery(name, attrs \\ []) do
    generate(
      order(
        [
          state: :placed,
          customer_name: name,
          fulfillment_method: :delivery,
          fulfillment_date: @date,
          fulfillment_status: :pending,
          position: "63.09,21.61",
          geocoded_address: "Storgatan 1, 65100 Vasa"
        ] ++ attrs
      )
    )
  end

  defp helsinki(time), do: DateTime.new!(@date, time, "Europe/Helsinki")

  test "sends only the day's undelivered, geocoded deliveries and returns them in HERE's order", %{admin: admin} do
    first = delivery("First")
    second = delivery("Second", fulfillment_time_start: ~T[10:00:00], fulfillment_time_end: ~T[10:30:00])
    delivered = delivery("Delivered", fulfillment_status: :fulfilled)
    unplaced = delivery("No address", position: nil)
    other_day = delivery("Other day", fulfillment_date: Date.add(@date, 1))

    shop = HereAPI.shop_position()

    expect(HereAPI.Mock, :sequence, fn ^shop, stops, ^shop, departure, :distance ->
      assert departure == helsinki(~T[09:00:00])
      assert stops |> Enum.map(& &1.id) |> Enum.sort() == Enum.sort([first.id, second.id])

      windowed = Enum.find(stops, &(&1.id == second.id))
      assert windowed.window == {helsinki(~T[10:00:00]), helsinki(~T[10:30:00])}

      {:ok,
       %{
         stops: [
           %{id: second.id, starts_at: helsinki(~T[10:00:00])},
           %{id: first.id, starts_at: helsinki(~T[10:20:00])}
         ],
         back_at: helsinki(~T[10:45:00]),
         distance: 14_905,
         driving: 1788
       }}
    end)

    ids = Enum.map([first, second, delivered, unplaced, other_day], & &1.id)
    route = Fulfillment.plan_route!(ids, @date, :shop, :shop, ~T[09:00:00], actor: admin)

    assert route.error == nil
    assert Enum.map(route.stops, & &1.order.id) == [second.id, first.id]
    assert hd(route.stops).starts_at == helsinki(~T[10:00:00])
    assert route.distance == 14_905
  end

  test "names a delivery its agreed time can't be met for", %{admin: admin} do
    late = delivery("Late", fulfillment_time_start: ~T[08:00:00], fulfillment_time_end: ~T[08:10:00])

    # HERE meets a window it can't make today a week later.
    expect(HereAPI.Mock, :sequence, fn _start, _stops, _finish, _departure, _optimise_for ->
      {:ok,
       %{
         stops: [%{id: late.id, starts_at: DateTime.add(helsinki(~T[08:00:00]), 7, :day)}],
         back_at: DateTime.add(helsinki(~T[08:20:00]), 7, :day),
         distance: 8000,
         driving: 900
       }}
    end)

    route = Fulfillment.plan_route!([late.id], @date, :shop, :shop, ~T[09:00:00], actor: admin)
    assert {:missed_windows, [%{id: id}]} = route.error
    assert id == late.id
  end

  test "can ignore agreed times and finish soonest", %{admin: admin} do
    late = delivery("Late", fulfillment_time_start: ~T[08:00:00], fulfillment_time_end: ~T[08:10:00])

    expect(HereAPI.Mock, :sequence, fn _start, [stop], _finish, _departure, :time ->
      assert stop.window == nil

      {:ok,
       %{
         stops: [%{id: late.id, starts_at: helsinki(~T[09:10:00])}],
         back_at: helsinki(~T[09:20:00]),
         distance: 8000,
         driving: 900
       }}
    end)

    route =
      Fulfillment.plan_route!(
        [late.id],
        @date,
        :shop,
        :shop,
        ~T[09:00:00],
        %{ignore_times: true, optimise_for: :time},
        actor: admin
      )

    assert route.error == nil
    assert [%{order: %{id: id}}] = route.stops
    assert id == late.id
  end

  test "gives an order with only a start time a quarter of an hour either side", %{admin: admin} do
    order = delivery("At ten", fulfillment_time_start: ~T[10:00:00])

    expect(HereAPI.Mock, :sequence, fn _start, [stop], _finish, _departure, _optimise_for ->
      assert stop.window == {helsinki(~T[09:45:00]), helsinki(~T[10:15:00])}
      {:error, :route_not_planned}
    end)

    assert %{error: :route_not_planned} =
             Fulfillment.plan_route!([order.id], @date, :shop, :shop, ~T[09:00:00], actor: admin)
  end

  test "can start from Parkhemmet", %{admin: admin} do
    order = delivery("Somewhere")
    parkhemmet = Fulfillment.route_place_position(:parkhemmet)
    shop = HereAPI.shop_position()

    expect(HereAPI.Mock, :sequence, fn ^parkhemmet, _stops, ^shop, _departure, _optimise_for ->
      {:error, :route_not_planned}
    end)

    assert %{error: :route_not_planned} =
             Fulfillment.plan_route!([order.id], @date, :parkhemmet, :shop, ~T[09:00:00], actor: admin)
  end

  test "can't start from home until it's configured", %{admin: admin} do
    order = delivery("Somewhere")
    assert Fulfillment.route_places() == [:shop, :parkhemmet]

    assert %{error: :no_home} =
             Fulfillment.plan_route!([order.id], @date, :home, :shop, ~T[09:00:00], actor: admin)
  end

  test "is for admins only" do
    order = delivery("Somewhere")
    customer = generate(admin_user(admin: false))

    assert {:error, %Ash.Error.Forbidden{}} =
             Fulfillment.plan_route([order.id], @date, :shop, :shop, ~T[09:00:00], actor: customer)
  end
end
