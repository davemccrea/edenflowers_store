defmodule EdenflowersWeb.Admin.OrdersLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  alias AshAuthentication.Plug.Helpers

  setup %{conn: conn} do
    admin = generate(admin_user()) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(admin)

    %{conn: conn}
  end

  test "searches orders by order reference as well as customer name", %{conn: conn} do
    placed_order(order_reference: "ABC123", customer_name: "Ada Lovelace")
    placed_order(order_reference: "XYZ789", customer_name: "Grace Hopper")

    {:ok, view, _html} = live(conn, ~p"/admin/orders?search=abc1")

    assert has_element?(view, "[data-item-id]", "Ada Lovelace")
    refute has_element?(view, "[data-item-id]", "Grace Hopper")

    {:ok, view, _html} = live(conn, ~p"/admin/orders?search=grace")

    assert has_element?(view, "[data-item-id]", "Grace Hopper")
    refute has_element?(view, "[data-item-id]", "Ada Lovelace")
  end

  test "opens on the orders still to make, paid or not", %{conn: conn} do
    placed_order(customer_name: "To Make", paid: true, fulfillment_status: :pending)
    placed_order(customer_name: "Already Done", paid: true, fulfillment_status: :fulfilled)
    placed_order(customer_name: "Pays Later", fulfillment_status: :pending)
    placed_order(customer_name: "Called Off", fulfillment_status: :cancelled)

    {:ok, view, _html} = live(conn, ~p"/admin/orders")

    assert has_element?(view, "[data-item-id]", "To Make")
    assert has_element?(view, "[data-item-id]", "Pays Later")
    refute has_element?(view, "[data-item-id]", "Already Done")
    refute has_element?(view, "[data-item-id]", "Called Off")
    assert has_element?(view, ~s(nav a[aria-current="page"]), "Orders")
  end

  test "lists every placed order once the default filter is cleared", %{conn: conn} do
    placed_order(customer_name: "To Make", paid: true, fulfillment_status: :pending)
    placed_order(customer_name: "Already Done", paid: true, fulfillment_status: :fulfilled)

    {:ok, view, _html} = live(conn, ~p"/admin/orders")
    render_patch(view, ~p"/admin/orders")

    assert has_element?(view, "[data-item-id]", "To Make")
    assert has_element?(view, "[data-item-id]", "Already Done")
  end

  test "filtering by unpaid lists orders still owed for, fulfilled or not", %{conn: conn} do
    placed_order(customer_name: "Paid Up", paid: true, fulfillment_status: :pending)

    placed_order(customer_name: "Delivered Unpaid", fulfillment_status: :fulfilled)

    {:ok, view, _html} = live(conn, ~p"/admin/orders?payment_status=pending")

    assert has_element?(view, "[data-item-id]", "Delivered Unpaid")
    refute has_element?(view, "[data-item-id]", "Paid Up")
  end

  test "flags orders still to fulfil whose fulfillment date has passed", %{conn: conn} do
    last_week = Date.add(Date.utc_today(), -7)
    late = placed_order(customer_name: "Late", fulfillment_date: last_week, fulfillment_status: :pending)
    done = placed_order(customer_name: "Done", fulfillment_date: last_week, fulfillment_status: :fulfilled)

    {:ok, view, _html} = live(conn, ~p"/admin/orders")

    assert has_element?(view, ~s([data-item-id="#{late.id}"]), "Overdue")
    refute has_element?(view, ~s([data-item-id="#{done.id}"]), "Overdue")
  end

  test "flags orders with money still to collect", %{conn: conn} do
    mismatched = placed_order(customer_name: "Mismatched", paid: "0.01")
    matching = placed_order(customer_name: "Matching", paid: true)

    {:ok, view, _html} = live(conn, ~p"/admin/orders")

    assert has_element?(view, ~s([data-item-id="#{mismatched.id}"]), "To collect")
    refute has_element?(view, ~s([data-item-id="#{matching.id}"]), "To collect")
  end

  test "marks orders a subscription created", %{conn: conn} do
    occurrence = placed_order(customer_name: "Subscriber", origin: :subscription)
    online = placed_order(customer_name: "Shopper")

    {:ok, view, _html} = live(conn, ~p"/admin/orders")

    assert has_element?(view, ~s([data-item-id="#{occurrence.id}"]), "Subscription")
    refute has_element?(view, ~s([data-item-id="#{online.id}"]), "Subscription")
  end
end
