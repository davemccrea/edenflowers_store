defmodule EdenflowersWeb.Admin.DashboardLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator

  alias AshAuthentication.Plug.Helpers

  test "renders the current admin account menu using the first-name calculation", %{conn: conn} do
    admin = generate(admin_user(name: "Jane Doe", email: "jane@example.com")) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(admin)

    {:ok, _view, html} = live(conn, ~p"/admin")

    assert html =~ "Admin account menu"
    assert html =~ "Jane"
    assert html =~ "jane@example.com"
    assert html =~ "JD"
    refute html =~ "Jane Doe"
  end

  test "links upcoming order rows to the order detail page", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(admin)

    order =
      generate(
        order(
          state: :placed,
          customer_name: "Ada Lovelace",
          fulfillment_method: :pickup,
          fulfillment_date: ~D[2026-06-10],
          fulfillment_status: :pending,
          grand_total: "42.00",
          ordered_at: DateTime.utc_now()
        )
      )

    {:ok, view, _html} = live(conn, ~p"/admin")

    assert has_element?(view, ~s|a[href="/admin/orders/#{order.id}"]|, "Ada Lovelace")
  end

  test "shows paid sales and revenue for the current month only", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(admin)

    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    variant = generate(product_variant(product_id: product.id, price: "40.00"))

    placed = fn ordered_at, payment_status, amount_paid ->
      order_attrs = [
        state: :placed,
        fulfillment_status: :fulfilled,
        fulfillment_fee: "5.00",
        ordered_at: ordered_at
      ]

      order =
        generate(order(order_attrs))

      generate(line_item(order_id: order.id, product_variant_id: variant.id))
      generate(payment(order_id: order.id, amount: Decimal.new(amount_paid), paid_at: ordered_at))

      if payment_status == :refunded,
        do: generate(payment(order_id: order.id, amount: Decimal.negate(Decimal.new(amount_paid)), paid_at: ordered_at))
    end

    now = DateTime.utc_now()
    placed.(now, :paid, "45.00")
    placed.(now, :paid, "45.00")
    placed.(now, :refunded, "45.00")
    placed.(DateTime.add(now, -40, :day), :paid, "45.00")

    {:ok, view, _html} = live(conn, ~p"/admin")

    sales = view |> element("dl") |> render()
    assert sales =~ ~r/>\s*2\s*</
    assert sales =~ "90.00"
  end
end
