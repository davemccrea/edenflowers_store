defmodule EdenflowersWeb.Admin.DeliveriesLiveTest do
  use EdenflowersWeb.ConnCase, async: false

  import Generator
  import Phoenix.LiveViewTest
  import Mox

  alias AshAuthentication.Jwt
  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.HereTourPlanning.{Assignment, Plan, Stop}

  setup :set_mox_global
  setup :verify_on_exit!

  setup %{conn: conn} do
    admin = generate(admin_user()) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(admin)

    %{conn: conn}
  end

  defp today, do: DateTime.now!("Europe/Helsinki") |> DateTime.to_date()

  defp eligible_order do
    generate(
      order(
        state: :placed,
        payment_status: :paid,
        fulfillment_status: :pending,
        fulfillment_method: :delivery,
        fulfillment_date: today(),
        order_reference: "EF-#{System.unique_integer([:positive])}",
        recipient_name: "Recipient",
        delivery_address: "Some Street 1, 65100 Vaasa",
        position: "63.1,21.6"
      )
    )
  end

  defp plan_for(driver, orders) do
    stops =
      orders
      |> Enum.with_index(1)
      |> Enum.map(fn {o, i} -> %Stop{order_id: o.id, sequence: i, leg_distance: 1000 * i, leg_duration: 600} end)

    %Plan{
      assignments: [
        %Assignment{
          vehicle_id: driver.id,
          stops: stops,
          total_distance: 1000 * length(orders),
          total_driving_duration: 600 * length(orders),
          total_service_duration: 300 * length(orders)
        }
      ]
    }
  end

  test "preselects eligible orders and the sole active driver", %{conn: conn} do
    order = eligible_order()
    generate(driver(name: "Solo Driver"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries")

    assert has_element?(view, "input[phx-value-id='#{order.id}'][checked]")
    assert render(view) =~ "Solo Driver"
  end

  test "optimize then publish creates a route and emails the driver", %{conn: conn} do
    order = eligible_order()
    driver = generate(driver(name: "Erik"))

    expect(Edenflowers.HereTourPlanning.Mock, :optimize, fn _input -> {:ok, plan_for(driver, [order])} end)

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries")

    view |> element("button[phx-click=optimize]") |> render_click()
    assert render(view) =~ "Publish and email drivers"

    view |> element("button[phx-click=publish]") |> render_click()

    html = render(view)
    assert html =~ "Published routes"
    assert html =~ order.order_reference
    assert html =~ "Erik"
  end

  test "rejects optimizing with more drivers than orders", %{conn: conn} do
    _order = eligible_order()
    generate(driver(name: "Driver A"))
    generate(driver(name: "Driver B"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries")

    # Select the second driver too (one order, two drivers).
    drivers = Edenflowers.Store.Driver.list_active!(actor: %{admin: true})

    Enum.each(drivers, fn d ->
      view |> element("input[phx-click=toggle_driver][phx-value-id='#{d.id}']:not([checked])") |> render_click()
    end)

    view |> element("button[phx-click=optimize]") |> render_click()
    assert render(view) =~ "more drivers than selected orders"
  end

  test "past dates show no planning panel", %{conn: conn} do
    yesterday = Date.add(today(), -1) |> Date.to_iso8601()

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries?date=#{yesterday}")

    refute has_element?(view, "button[phx-click=optimize]")
  end

  defp with_token(user) do
    {:ok, token, _claims} = Jwt.token_for_user(user)
    %{user | __metadata__: Map.put(user.__metadata__, :token, token)}
  end
end
