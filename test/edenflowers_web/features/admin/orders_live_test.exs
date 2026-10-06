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

  test "the default path lists every order still to fulfil, paid or not", %{conn: conn} do
    placed_order(customer_name: "To Make", payment_status: :paid, fulfillment_status: :pending)
    placed_order(customer_name: "Already Done", payment_status: :paid, fulfillment_status: :fulfilled)
    placed_order(customer_name: "Pays Later", payment_status: :pending, fulfillment_status: :pending)
    placed_order(customer_name: "Called Off", payment_status: :pending, fulfillment_status: :cancelled)

    {:ok, view, _html} = live(conn, EdenflowersWeb.Admin.OrdersLive.default_path())

    assert has_element?(view, "[data-item-id]", "To Make")
    assert has_element?(view, "[data-item-id]", "Pays Later")
    refute has_element?(view, "[data-item-id]", "Already Done")
    refute has_element?(view, "[data-item-id]", "Called Off")
    assert has_element?(view, ~s(nav a[aria-current="page"]), "Orders")
  end

  test "filtering by unpaid lists orders still owed for, fulfilled or not", %{conn: conn} do
    placed_order(customer_name: "Paid Up", payment_status: :paid, fulfillment_status: :pending)
    placed_order(customer_name: "Delivered Unpaid", payment_status: :pending, fulfillment_status: :fulfilled)

    {:ok, view, _html} = live(conn, ~p"/admin/orders?payment_status=pending")

    assert has_element?(view, "[data-item-id]", "Delivered Unpaid")
    refute has_element?(view, "[data-item-id]", "Paid Up")
  end

  test "flags orders still to fulfil whose fulfillment date has passed", %{conn: conn} do
    last_week = Date.add(Date.utc_today(), -7)
    late = placed_order(customer_name: "Late", fulfillment_date: last_week, fulfillment_status: :pending)
    done = placed_order(customer_name: "Done", fulfillment_date: last_week, fulfillment_status: :fulfilled)

    {:ok, view, _html} = live(conn, ~p"/admin/orders")

    assert has_element?(view, ~s([data-item-id="#{late.id}"] .admin-badge-error), "Overdue")
    refute has_element?(view, ~s([data-item-id="#{done.id}"] .admin-badge-error))
  end

  test "flags orders with money still to collect", %{conn: conn} do
    mismatched = placed_order(customer_name: "Mismatched")
    generate(payment(order_id: mismatched.id, amount: Decimal.new("0.01")))
    matching = placed_order(customer_name: "Matching")
    variant = generate(product_variant(product_id: generate(product()).id))
    generate(line_item(order_id: mismatched.id, product_variant_id: variant.id))

    {:ok, view, _html} = live(conn, ~p"/admin/orders")

    assert has_element?(view, ~s([data-item-id="#{mismatched.id}"] .admin-badge-error), "To collect")
    refute has_element?(view, ~s([data-item-id="#{matching.id}"] .admin-badge-error))
  end

  defp placed_order(attrs) do
    generate(order([state: :placed, ordered_at: DateTime.utc_now(), locale: "en-GB"] ++ attrs))
  end
end
