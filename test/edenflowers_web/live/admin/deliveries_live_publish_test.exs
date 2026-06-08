defmodule EdenflowersWeb.Admin.DeliveriesLivePublishTest do
  # async: false — publishing opens a transaction that writes routes + stops across tables;
  # run serially to avoid lock contention with other tests creating orders concurrently.
  use EdenflowersWeb.ConnCase, async: false

  import Generator
  import Phoenix.LiveViewTest

  alias AshAuthentication.Jwt
  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.Delivery.{Route, RouteStop}
  alias Edenflowers.Store.Order

  setup %{conn: conn} do
    admin = generate(admin_user()) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(admin)

    %{conn: conn, admin: admin}
  end

  defp eligible_order(overrides) do
    today = DateTime.now!("Europe/Helsinki") |> DateTime.to_date()

    defaults = [
      state: :placed,
      payment_status: :paid,
      fulfillment_status: :pending,
      fulfillment_method: :delivery,
      fulfillment_date: today,
      position: "63.0951,21.6165",
      ordered_at: DateTime.utc_now()
    ]

    generate(order(Keyword.merge(defaults, overrides)))
  end

  defp optimize(view) do
    view |> element("button[phx-click=optimize]") |> render_click()
  end

  defp publish(view) do
    view |> element("button[phx-click=publish]") |> render_click()
    assert_redirect(view, ~p"/admin/deliveries")
  end

  test "publishing snapshots the order and removes it from eligibility", %{conn: conn} do
    product = generate(product(name: "Roses"))
    variant = generate(product_variant(product_id: product.id))
    card_product = generate(product(name: "Gift card"))
    card_variant = generate(product_variant(product_id: card_product.id))

    order =
      eligible_order(
        order_reference: "EF-PUB",
        recipient_name: "Alice",
        delivery_address: "Some Street 1",
        card_message: "Happy Birthday"
      )

    generate(line_item(order_id: order.id, product_variant_id: variant.id, quantity: 2))
    generate(line_item(order_id: order.id, product_variant_id: card_variant.id, is_card: true))

    generate(driver(name: "Dana"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries/plan")
    optimize(view)
    publish(view)
    {:ok, overview, html} = live(conn, ~p"/admin/deliveries")

    assert has_element?(overview, "#today-routes")
    assert html =~ "Dana"
    assert html =~ "EF-PUB"
    assert html =~ "Alice"

    assert [stop] = Ash.read!(RouteStop, authorize?: false)
    assert stop.order_id == order.id
    assert stop.order_reference == "EF-PUB"
    assert stop.recipient_name == "Alice"
    assert stop.delivery_address == "Some Street 1"
    assert stop.card_message == "Happy Birthday"

    assert Enum.sort_by(stop.products, & &1["name"]) == [
             %{"name" => "Gift card", "quantity" => 1},
             %{"name" => "Roses", "quantity" => 2}
           ]

    assert stop.leg_distance_m == 2_000

    # The published order is no longer eligible, and its planning checkbox is gone.
    today = DateTime.now!("Europe/Helsinki") |> DateTime.to_date()
    assert {:ok, []} = Order.list_eligible_for_delivery(%{date: today}, authorize?: false)
  end

  test "a second run plans only the orders left after the first is published", %{conn: conn} do
    first = eligible_order(order_reference: "EF-FIRST")
    second = eligible_order(order_reference: "EF-SECOND")
    generate(driver(name: "Dana"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries/plan")

    # Publish only the first order.
    view |> element("input#order-#{second.id}") |> render_click()
    optimize(view)
    publish(view)

    # The second order remains eligible and selectable for another run.
    {:ok, next_plan, _html} = live(conn, ~p"/admin/deliveries/plan")
    assert has_element?(next_plan, "input#order-#{second.id}")
    refute has_element?(next_plan, "input#order-#{first.id}")
  end

  test "the florist can cancel an untouched route and plan its order again", %{
    conn: conn,
    admin: admin
  } do
    eligible_order(order_reference: "EF-CANCEL")
    generate(driver(name: "Dana"))

    {:ok, plan, _html} = live(conn, ~p"/admin/deliveries/plan")
    optimize(plan)
    publish(plan)

    [route] = Route.list_published_for_date!(today(), actor: admin)
    {:ok, view, _html} = live(conn, ~p"/admin/deliveries")

    view
    |> element("#cancel-route-#{route.id}")
    |> render_click()

    refute has_element?(view, "#route-monitor-#{route.id}")
    assert has_element?(view, "#plan-dispatch")
    assert render(view) =~ "Route cancelled"
  end

  test "publishes multiple proposed routes assigned to the same driver", %{conn: conn, admin: admin} do
    eligible_order(order_reference: "EF-REASSIGNED-1")
    eligible_order(order_reference: "EF-REASSIGNED-2")
    first = generate(driver(name: "Driver A"))
    second = generate(driver(name: "Driver B"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries/plan")
    view |> element("input#driver-#{first.id}") |> render_click()
    view |> element("input#driver-#{second.id}") |> render_click()
    optimize(view)

    for draft_id <- ["0", "1"] do
      view
      |> form("#route-driver-form-#{draft_id}")
      |> render_change(%{
        "assignment" => %{"draft_id" => draft_id, "driver_id" => first.id}
      })
    end

    publish(view)

    routes = Route.list_published_for_date!(today(), actor: admin)
    assert length(routes) == 2
    assert Enum.all?(routes, &(&1.driver_id == first.id))
  end

  test "a second published run appears without disturbing the first run's progress", %{
    conn: conn,
    admin: admin
  } do
    _first = eligible_order(order_reference: "EF-FIRST")
    second = eligible_order(order_reference: "EF-SECOND")
    generate(driver(name: "Dana"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries/plan")

    view |> element("input#order-#{second.id}") |> render_click()
    optimize(view)
    publish(view)

    [first_route] = Route.list_published_for_date!(today(), actor: admin)
    [first_stop] = first_route.route_stops

    RouteStop.record_failed!(
      first_stop,
      %{failure_reason: :recipient_unavailable},
      actor: admin
    )

    {:ok, overview, _html} = live(conn, ~p"/admin/deliveries")
    assert has_element?(overview, "#route-failed-#{first_route.id}", "1 Failed")

    {:ok, second_plan, _html} = live(conn, ~p"/admin/deliveries/plan")
    optimize(second_plan)
    publish(second_plan)

    routes = Route.list_published_for_date!(today(), actor: admin)
    assert length(routes) == 2

    second_route = Enum.find(routes, &(&1.id != first_route.id))
    {:ok, overview, _html} = live(conn, ~p"/admin/deliveries")
    assert has_element?(overview, "#route-monitor-#{first_route.id}")
    assert has_element?(overview, "#route-failed-#{first_route.id}", "1 Failed")
    assert has_element?(overview, "#route-monitor-#{second_route.id}")
    assert has_element?(overview, "#route-remaining-#{second_route.id}", "1 Remaining")

    [second_stop] = second_route.route_stops

    RouteStop.record_delivered!(
      second_stop,
      %{delivery_method: :handed_to_recipient},
      actor: admin
    )

    render(overview)
    assert has_element?(overview, "#route-delivered-#{second_route.id}", "1 Delivered")
    assert has_element?(overview, "#route-monitor-#{second_route.id}", "Completed")
  end

  defp today, do: DateTime.now!("Europe/Helsinki") |> DateTime.to_date()

  defp with_token(user) do
    {:ok, token, _claims} = Jwt.token_for_user(user)
    %{user | __metadata__: Map.put(user.__metadata__ || %{}, :token, token)}
  end
end
