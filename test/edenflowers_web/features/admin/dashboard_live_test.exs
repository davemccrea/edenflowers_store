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

    {:ok, view, html} = live(conn, ~p"/admin")

    assert has_element?(view, "h1", "Hi, Jane")
    assert html =~ "Eden Flowers | Overview"
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

  test "shows an order placed elsewhere without a refresh", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    conn = conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(admin)

    {:ok, view, _html} = live(conn, ~p"/admin")
    refute render(view) =~ "Grace Hopper"

    generate(
      order(
        state: :placed,
        customer_name: "Grace Hopper",
        fulfillment_method: :pickup,
        fulfillment_date: ~D[2026-06-10],
        fulfillment_status: :pending,
        grand_total: "42.00",
        ordered_at: DateTime.utc_now()
      )
    )

    EdenflowersWeb.Endpoint.broadcast("admin:orders", "finalize_checkout", %{})

    assert render(view) =~ "Grace Hopper"
  end

  describe "to collect / to refund" do
    setup %{conn: conn} do
      admin = generate(admin_user()) |> with_token()
      %{conn: conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(admin)}
    end

    test "groups what's owed either way, with counts, sums and links", %{conn: conn} do
      order = placed_order(customer_name: "Ada Lovelace", fulfillment_status: :fulfilled, payment_intent_id: nil)
      course = generate(course(name: "Autumn wreaths"))

      registration =
        generate(
          course_registration(course_id: course.id, status: :cancelled, name: "Birgitta", amount: Decimal.new("85.00"))
        )

      generate(payment(course_registration_id: registration.id, amount: Decimal.new("85.00"), method: :cash))

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, ~s|#balances section[aria-label="To collect"]|, "To collect · 1")
      assert has_element?(view, ~s|#balances section[aria-label="To collect"]|, "€88.50")
      assert has_element?(view, ~s|#balance-order-#{order.id} a[href="/admin/orders/#{order.id}"]|, "Ada Lovelace")

      assert has_element?(view, ~s|#balances section[aria-label="To refund"]|, "To refund · 1")
      assert has_element?(view, ~s|#balances section[aria-label="To refund"]|, "€85.00")

      assert has_element?(
               view,
               ~s|#balance-booking-#{registration.id} a[href="/admin/courses#course-#{course.id}"]|,
               "Autumn wreaths"
             )
    end

    test "is hidden when nothing is owed", %{conn: conn} do
      placed_order(paid: true)

      {:ok, view, _html} = live(conn, ~p"/admin")

      refute has_element?(view, "#balances")
    end

    test "settles an order paid while the Overview is open", %{conn: conn} do
      order = placed_order(payment_intent_id: "pi_link")

      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, "#balance-order-#{order.id}")

      {:ok, _order} =
        Edenflowers.Orders.record_link_payment(order, "pi_link", %{amount_paid: order.grand_total},
          actor: Edenflowers.Actors.system_actor()
        )

      refute has_element?(view, "#balance-order-#{order.id}")
    end
  end

  test "shows paid sales and revenue for the current month only", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(admin)

    now = DateTime.utc_now()
    placed_order(ordered_at: now, paid: "45.00")
    placed_order(ordered_at: now, paid: "45.00")
    placed_order(ordered_at: now, paid: "45.00", refunded: true)
    placed_order(ordered_at: DateTime.add(now, -40, :day), paid: "45.00")

    {:ok, view, _html} = live(conn, ~p"/admin")

    sales = view |> element("dl") |> render()
    assert sales =~ ~r/>\s*2\s*</
    assert sales =~ "90.00"
  end

  test "pauses and reopens same-day orders for today", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    conn = conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(admin)
    generate(fulfillment_option())

    {:ok, view, _html} = live(conn, ~p"/admin")
    assert has_element?(view, "#same-day", "Open for today")

    view |> element("#same-day form") |> render_change(%{"open" => "false"})
    assert has_element?(view, "#same-day", "Paused for today")
    assert Edenflowers.Fulfillment.same_day_today(authorize?: false) == :paused

    view |> element("#same-day form") |> render_change(%{"open" => "true"})
    assert has_element?(view, "#same-day", "Open for today")
  end
end
