defmodule EdenflowersWeb.Admin.RouteDrawerTest do
  use EdenflowersWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest
  import Generator

  alias Edenflowers.External.HereAPI
  alias EdenflowersWeb.Admin.RouteDrawer

  setup :verify_on_exit!

  describe "on the overview" do
    setup :log_in_admin

    defp delivery(name, attrs \\ []) do
      generate(
        order(
          [
            state: :placed,
            customer_name: name,
            fulfillment_method: :delivery,
            fulfillment_date: Edenflowers.ShopTime.today(),
            fulfillment_status: :ready,
            position: "63.09,21.61",
            geocoded_address: "#{name}vägen 1, 65100 Vasa"
          ] ++ attrs
        )
      )
    end

    test "plans the ticked deliveries and starts the run at its first stop", %{conn: conn, admin: admin} do
      near = delivery("Near")
      far = delivery("Far", position: "63.20,21.70")
      skipped = delivery("Skipped")
      unmade = delivery("Unmade", fulfillment_status: :pending)
      unplaced = delivery("Unplaced", position: nil)

      expect(HereAPI.Mock, :sequence, fn _start, stops, _finish, _departure ->
        assert stops |> Enum.map(& &1.id) |> Enum.sort() == Enum.sort([near.id, far.id])
        today = Edenflowers.ShopTime.today()

        {:ok,
         %{
           stops: [
             %{id: far.id, starts_at: DateTime.new!(today, ~T[09:20:00], "Europe/Helsinki")},
             %{id: near.id, starts_at: DateTime.new!(today, ~T[09:40:00], "Europe/Helsinki")}
           ],
           back_at: DateTime.new!(today, ~T[10:00:00], "Europe/Helsinki"),
           distance: 21_500,
           driving: 2400
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/admin")
      view |> element("#day-orders-route") |> render_click()

      assert has_element?(view, "#route-stop-#{skipped.id}[checked]")
      # Only made orders start ticked; one that isn't Ready can still be ticked by hand.
      assert has_element?(view, "#route-stop-#{unmade.id}:not([checked])")
      assert has_element?(view, "#route-unplaced a[href='/admin/orders/#{unplaced.id}']", "Unplaced")
      refute has_element?(view, "#route-stop-#{unplaced.id}")

      view
      |> form("#route-form", route: %{stops: [near.id, far.id], departure: "09:00"})
      |> render_submit()

      assert has_element?(view, "#route-1", "Far")
      assert has_element?(view, "#route-2", "Near")
      assert has_element?(view, "#route-result", "21.5 km · 40 min")

      far_path = ~p"/admin/orders/#{far.id}"
      assert {:error, {:live_redirect, %{to: ^far_path}}} = view |> element("#start-delivery-run") |> render_click()

      saved = Edenflowers.Orders.get_order_by_id!(far.id, actor: admin)
      today = Edenflowers.ShopTime.today()
      assert DateTime.compare(saved.route_planned_at, DateTime.new!(today, ~T[09:20:00], "Europe/Helsinki")) == :eq
      assert DateTime.compare(saved.route_planned_back_at, DateTime.new!(today, ~T[10:00:00], "Europe/Helsinki")) == :eq

      # The order page's next arrow follows the run.
      queue = Edenflowers.Orders.list_orders_to_fulfil!(actor: admin)
      assert Enum.map(queue, & &1.id) |> Enum.take(2) == [far.id, near.id]
    end

    test "shows today's run at the top of the Overview, in stop order, with Directions to the next", %{conn: conn} do
      second = delivery("Second", route_position: 2)
      first = delivery("First", route_position: 1)
      delivered = delivery("Delivered", route_position: 3, fulfillment_status: :fulfilled)
      off_run = delivery("Off the run")

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#delivery-run li:nth-child(1)#delivery-run-stop-#{first.id}", "First")
      assert has_element?(view, "#delivery-run li:nth-child(2)#delivery-run-stop-#{second.id}", "Second")
      assert has_element?(view, "#delivery-run li:nth-child(3)#delivery-run-stop-#{delivered.id}", "Delivered")

      assert has_element?(
               view,
               "#delivery-run-stop-#{first.id} a#delivery-run-directions[href*='destination=Firstv%C3%A4gen+1%2C+65100+Vasa']"
             )

      refute has_element?(view, "#delivery-run-stop-#{second.id} a[href*='destination']")
      refute has_element?(view, "#delivery-run-stop-#{off_run.id}")
      assert has_element?(view, "#delivery-run-progress", "1 of 3 delivered")
    end

    test "plans again from today's run, saying a new run replaces it", %{conn: conn} do
      on_run = delivery("On the run", route_position: 1)
      off_run = delivery("Off the run")

      {:ok, view, _html} = live(conn, ~p"/admin")
      view |> element("#day-orders-route") |> render_click()

      assert has_element?(view, "#route-current-run", "1 stop left")
      assert has_element?(view, "#route-stop-#{on_run.id}[checked]")
      assert has_element?(view, "#route-stop-#{off_run.id}:not([checked])")
    end

    test "plans another day from its own Ready deliveries while today's run is on", %{conn: conn} do
      delivery("On the run", route_position: 1)
      tomorrow = delivery("Tomorrow", fulfillment_date: Date.add(Edenflowers.ShopTime.today(), 1))

      {:ok, view, _html} = live(conn, ~p"/admin")
      render_click(view, "open_route", %{"date" => Date.to_iso8601(tomorrow.fulfillment_date)})

      refute has_element?(view, "#route-current-run")
      assert has_element?(view, "#route-stop-#{tomorrow.id}[checked]")
    end

    test "keeps a route the form no longer matches, out of date and not startable", %{conn: conn} do
      order = delivery("Only")

      expect(HereAPI.Mock, :sequence, fn _start, _stops, _finish, _departure ->
        today = Edenflowers.ShopTime.today()

        {:ok,
         %{
           stops: [%{id: order.id, starts_at: DateTime.new!(today, ~T[09:20:00], "Europe/Helsinki")}],
           back_at: DateTime.new!(today, ~T[09:40:00], "Europe/Helsinki"),
           distance: 8000,
           driving: 900
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/admin")
      view |> element("#day-orders-route") |> render_click()
      view |> form("#route-form", route: %{departure: "09:00"}) |> render_submit()
      assert has_element?(view, "#start-delivery-run")

      view |> form("#route-form", route: %{departure: "10:00"}) |> render_change()

      assert has_element?(view, "#route-stale")
      assert has_element?(view, "#route-1", "Only")
      refute has_element?(view, "#start-delivery-run")
    end

    test "starts at the run's first stop when the planned first was delivered since", %{conn: conn} do
      gone = delivery("Gone")
      next = delivery("Next")

      expect(HereAPI.Mock, :sequence, fn _start, _stops, _finish, _departure ->
        today = Edenflowers.ShopTime.today()

        {:ok,
         %{
           stops: [
             %{id: gone.id, starts_at: DateTime.new!(today, ~T[09:20:00], "Europe/Helsinki")},
             %{id: next.id, starts_at: DateTime.new!(today, ~T[09:40:00], "Europe/Helsinki")}
           ],
           back_at: DateTime.new!(today, ~T[10:00:00], "Europe/Helsinki"),
           distance: 8000,
           driving: 900
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/admin")
      view |> element("#day-orders-route") |> render_click()
      view |> form("#route-form", route: %{departure: "09:00"}) |> render_submit()

      Ash.Seed.update!(gone, %{fulfillment_status: :fulfilled})

      next_path = ~p"/admin/orders/#{next.id}"
      assert {:error, {:live_redirect, %{to: ^next_path}}} = view |> element("#start-delivery-run") |> render_click()
    end

    test "ends the run from the Overview", %{conn: conn} do
      delivery("On the run", route_position: 1)
      {:ok, view, _html} = live(conn, ~p"/admin")

      view |> element("#end-delivery-run") |> render_click()

      refute has_element?(view, "#delivery-run")
    end

    test "shows no run section without a run", %{conn: conn} do
      delivery("Not on a run")
      {:ok, view, _html} = live(conn, ~p"/admin")
      refute has_element?(view, "#delivery-run")
    end

    test "won't let a route be planned with no stops or no time", %{conn: conn} do
      order = delivery("Only")

      {:ok, view, _html} = live(conn, ~p"/admin")
      view |> element("#day-orders-route") |> render_click()

      view |> form("#route-form", route: %{stops: [""]}) |> render_change()
      assert has_element?(view, "#route-form button[type=submit][disabled]")

      view |> form("#route-form", route: %{stops: [order.id], departure: ""}) |> render_submit()
      assert has_element?(view, "#route-result [role=alert]", "Check the stops and the leaving time")
    end

    test "says which delivery can't be reached in its agreed time", %{conn: conn} do
      late = delivery("Late", fulfillment_time_start: ~T[08:00:00], fulfillment_time_end: ~T[08:10:00])

      expect(HereAPI.Mock, :sequence, fn _start, _stops, _finish, _departure ->
        next_week = Date.add(Edenflowers.ShopTime.today(), 7)

        {:ok,
         %{
           stops: [%{id: late.id, starts_at: DateTime.new!(next_week, ~T[08:00:00], "Europe/Helsinki")}],
           back_at: DateTime.new!(next_week, ~T[08:20:00], "Europe/Helsinki"),
           distance: 8000,
           driving: 900
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/admin")
      view |> element("#day-orders-route") |> render_click()
      view |> form("#route-form", route: %{departure: "09:00"}) |> render_submit()

      assert has_element?(view, "#route-result [role=alert]", "Late")
      assert has_element?(view, "#route-form label", "Can't be reached in time")
    end
  end

  test "maps a route with its ends unnumbered and its stops numbered in driving order, longitude first" do
    stop = fn position -> %{order: %{position: position}} end
    route = %{start: "63.1,21.6", finish: "63.1,21.6", stops: [stop.("63.2,21.7"), stop.("63.05, 21.55")]}

    url = RouteDrawer.route_map_url(route, "tok")

    assert url =~ "pin-s+e8542b(21.6,63.1),pin-s-1+e8542b(21.7,63.2),pin-s-2+e8542b(21.55,63.05)/auto/"
    refute url =~ "pin-s+e8542b(21.6,63.1),pin-s+e8542b"
    line = url |> URI.decode() |> then(&Regex.run(~r/geojson\((.+?)\),pin/, &1, capture: :all_but_first)) |> hd()
    assert Jason.decode!(line)["geometry"]["coordinates"] == [[21.6, 63.1], [21.7, 63.2], [21.55, 63.05], [21.6, 63.1]]
    assert url =~ "access_token=tok"
  end
end
