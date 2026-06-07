defmodule EdenflowersWeb.Admin.DeliveriesLiveMonitorTest do
  use EdenflowersWeb.ConnCase, async: false

  import Generator
  import Phoenix.LiveViewTest

  alias AshAuthentication.Jwt
  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.Delivery.{Route, RouteStop}

  setup %{conn: conn} do
    admin = generate(admin_user()) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(admin)

    %{conn: conn, admin: admin}
  end

  test "an outcome broadcast patches progress and derived completion", %{conn: conn, admin: admin} do
    order = generate(order(fulfillment_status: :pending))
    driver = generate(driver(name: "Dana"))
    route = publish_route(driver, order, admin)
    [stop] = route.route_stops

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries")

    assert has_element?(view, "#route-delivered-#{route.id}", "0 Delivered")
    assert has_element?(view, "#route-failed-#{route.id}", "0 Failed")
    assert has_element?(view, "#route-remaining-#{route.id}", "1 Remaining")
    refute has_element?(view, "#route-monitor-#{route.id}", "Completed")

    RouteStop.record_delivered!(
      stop,
      %{delivery_method: :handed_to_recipient},
      actor: admin
    )

    render(view)

    assert has_element?(view, "#route-delivered-#{route.id}", "1 Delivered")
    assert has_element?(view, "#route-failed-#{route.id}", "0 Failed")
    assert has_element?(view, "#route-remaining-#{route.id}", "0 Remaining")
    assert has_element?(view, "#monitor-stop-#{stop.id}", "Delivered")
    assert has_element?(view, "#route-monitor-#{route.id}", "Completed")
  end

  test "each driver exposes copy and open-driver actions", %{conn: conn, admin: admin} do
    order = generate(order(fulfillment_status: :pending))
    driver = generate(driver(name: "Dana"))
    _route = publish_route(driver, order, admin)
    link = EdenflowersWeb.Endpoint.url() <> "/d/" <> driver.link_token

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries")

    assert has_element?(
             view,
             "#copy-driver-#{driver.id}[phx-hook=CopyToClipboard][data-clipboard-text='#{link}']"
           )

    assert has_element?(
             view,
             "#driver-routes-#{driver.id} a[href='/d/#{driver.link_token}'][target=_blank]",
             "Open driver view"
           )
  end

  defp publish_route(driver, order, actor) do
    today = DateTime.now!("Europe/Helsinki") |> DateTime.to_date()

    Route.publish!(
      %{
        date: today,
        driver_id: driver.id,
        stops: [
          %{
            sequence: 1,
            order_id: order.id,
            order_reference: order.order_reference,
            recipient_name: order.recipient_name,
            products: [],
            leg_distance_m: 2_000,
            leg_duration_s: 300
          }
        ]
      },
      actor: actor
    )
    |> Ash.load!([:driver, :route_stops], actor: actor)
  end

  defp with_token(user) do
    {:ok, token, _claims} = Jwt.token_for_user(user)
    %{user | __metadata__: Map.put(user.__metadata__ || %{}, :token, token)}
  end
end
