defmodule EdenflowersWeb.Admin.OverviewLiveTest do
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

  test "links order rows to the order detail page", %{conn: conn} do
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

  describe "today and tomorrow" do
    setup %{conn: conn} do
      admin = generate(admin_user()) |> with_token()
      %{conn: conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(admin)}
    end

    defp open_order(name, method, days_from_today) do
      generate(
        order(
          state: :placed,
          customer_name: name,
          fulfillment_method: method,
          fulfillment_date: Date.add(Edenflowers.ShopTime.today(), days_from_today),
          fulfillment_status: :pending
        )
      )
    end

    test "lists today's and tomorrow's orders by method, and nothing later", %{conn: conn} do
      open_order("Today Delivery", :delivery, 0)
      open_order("Today Pickup", :pickup, 0)
      open_order("Tomorrow Pickup", :pickup, 1)
      open_order("Next Week", :pickup, 7)
      open_order("Last Week", :pickup, -7)

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, ~s|#orders-today section[aria-label="Deliveries"]|, "Today Delivery")
      assert has_element?(view, ~s|#orders-today section[aria-label="Pickups"]|, "Today Pickup")
      assert has_element?(view, ~s|#orders-today section[aria-label="Overdue"]|, "Last Week")
      assert has_element?(view, ~s|#orders-tomorrow section[aria-label="Pickups"]|, "Tomorrow Pickup")
      refute has_element?(view, ~s|#orders-tomorrow section[aria-label="Deliveries"]|)
      refute render(view) =~ "Next Week"
    end

    test "says so when a day has nothing to make", %{conn: conn} do
      open_order("Tomorrow Pickup", :pickup, 1)

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#orders-today", "Nothing to make today")
      refute has_element?(view, "#orders-tomorrow", "Nothing to make tomorrow")
    end
  end

  test "flags a delivery with no phone to call", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    conn = conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(admin)

    attrs = [
      state: :placed,
      fulfillment_method: :delivery,
      fulfillment_date: ~D[2026-06-10],
      fulfillment_status: :pending,
      gift: true
    ]

    missing = generate(order([customer_name: "No Phone"] ++ attrs))
    phoned = generate(order([customer_name: "Has Phone", recipient_phone_number: "+358401234567"] ++ attrs))

    {:ok, view, _html} = live(conn, ~p"/admin")

    assert has_element?(view, ~s|a[href="/admin/orders/#{missing.id}"]|, "Missing recipient phone")
    refute has_element?(view, ~s|a[href="/admin/orders/#{phoned.id}"]|, "Missing recipient phone")
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
               ~s|#balance-booking-#{registration.id} a[href="/admin/courses?booking=#{registration.id}#registration-#{registration.id}"]|,
               "Autumn wreaths"
             )
    end

    test "shows the five largest of a group and tucks the rest behind Show more", %{conn: conn} do
      for _ <- 1..7, do: placed_order(fulfillment_status: :fulfilled, payment_intent_id: nil)

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, ~s|#balances section[aria-label="To collect"]|, "To collect · 7")
      assert has_element?(view, "#balances-more-collect summary", "Show 2 more")
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
end
