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
          fulfillment_date: Edenflowers.ShopTime.today(),
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

      assert has_element?(view, ~s|#orders-today-delivery|, "Today Delivery")
      assert has_element?(view, ~s|#orders-today-pickup|, "Today Pickup")
      refute has_element?(view, "#orders-today", "Last Week")
      assert has_element?(view, ~s|#orders-tomorrow-pickup|, "Tomorrow Pickup")
      refute has_element?(view, ~s|#orders-tomorrow-delivery|)
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
      fulfillment_date: Edenflowers.ShopTime.today(),
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
        fulfillment_date: Edenflowers.ShopTime.today(),
        fulfillment_status: :pending,
        grand_total: "42.00",
        ordered_at: DateTime.utc_now()
      )
    )

    EdenflowersWeb.Endpoint.broadcast("admin:orders", "finalize_checkout", %{})

    assert render(view) =~ "Grace Hopper"
  end

  describe "needs attention" do
    setup %{conn: conn} do
      admin = generate(admin_user()) |> with_token()
      %{conn: conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(admin)}
    end

    test "is hidden when nothing needs Jennie", %{conn: conn} do
      placed_order(paid: true, fulfillment_status: :fulfilled)

      {:ok, view, _html} = live(conn, ~p"/admin")

      refute has_element?(view, "#attention")
      refute has_element?(view, "#still-owed")
    end

    test "lists overdue orders but leaves a missing phone to the order row badge", %{conn: conn} do
      today = Edenflowers.ShopTime.today()

      overdue =
        generate(
          order(
            state: :placed,
            customer_name: "Late",
            fulfillment_date: Date.add(today, -2),
            fulfillment_status: :pending
          )
        )

      generate(
        order(
          state: :placed,
          customer_name: "No Phone",
          fulfillment_method: :delivery,
          fulfillment_date: Date.add(today, 1),
          fulfillment_status: :pending,
          gift: true
        )
      )

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#attention-overdue-orders summary", "Overdue orders · 1")
      assert has_element?(view, ~s|#attention-overdue-orders a[href="/admin/orders/#{overdue.id}"]|, "Late")
      refute has_element?(view, "#attention-missing-phone")
      assert render(view) =~ "Missing recipient phone"
    end

    test "lists subscriptions whose payment failed", %{conn: conn} do
      failed = generate(subscription(state: :payment_failed))
      generate(subscription(state: :active))

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#attention-failed-subscriptions summary", "Subscription payment failed · 1")
      assert has_element?(view, ~s|#attention-failed-subscriptions a[href="/admin/subscriptions/#{failed.id}"]|)
    end

    test "lists sizes on sale that have sold out", %{conn: conn} do
      category = generate(product_category(visibility: :public))
      product = generate(product(name: "Peony bouquet", draft: false, product_category_id: category.id))
      generate(product_variant(product_id: product.id, stock_quantity: 0, draft: false))
      generate(product_variant(product_id: product.id, size: :large, stock_quantity: 3, draft: false))

      hidden = generate(product(draft: true, product_category_id: category.id))
      generate(product_variant(product_id: hidden.id, stock_quantity: 0, draft: false))

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#attention-sold-out summary", "Sold out · 1")
      assert has_element?(view, ~s|#attention-sold-out a[href="/admin/products/#{product.id}"]|, "Peony bouquet")
    end

    test "flags refunds and overdue payments, and totals what orders still owe", %{conn: conn} do
      overdue = placed_order(customer_name: "Ada Lovelace", fulfillment_status: :fulfilled, payment_intent_id: nil)

      placed_order(
        customer_name: "Grace Hopper",
        fulfillment_status: :fulfilled,
        fulfillment_date: Date.add(Edenflowers.ShopTime.today(), -3),
        payment_intent_id: nil
      )

      course = generate(course(name: "Autumn wreaths"))

      registration =
        generate(
          course_registration(course_id: course.id, status: :cancelled, name: "Birgitta", amount: Decimal.new("85.00"))
        )

      generate(payment(course_registration_id: registration.id, amount: Decimal.new("85.00"), method: :cash))

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#attention-payment-overdue summary", "Payment overdue · 1")
      assert has_element?(view, "#attention-payment-overdue summary", "€88.50")
      assert has_element?(view, ~s|#attention-payment-overdue a[href="/admin/orders/#{overdue.id}"]|, "Ada Lovelace")

      assert has_element?(view, "#attention-refund summary", "To refund · 1")
      assert has_element?(view, "#attention-refund summary", "€85.00")

      assert has_element?(
               view,
               ~s|#attention-refund a[href="/admin/courses?booking=#{registration.id}#registration-#{registration.id}"]|,
               "Autumn wreaths"
             )

      refute has_element?(view, "#attention", "Grace Hopper")
      assert has_element?(view, "#still-owed", "€177.00")
    end

    test "settles an order paid while the Overview is open", %{conn: conn} do
      order = placed_order(payment_intent_id: "pi_link", fulfillment_date: Edenflowers.ShopTime.today())

      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, "#still-owed", "€88.50")

      {:ok, _order} =
        Edenflowers.Orders.record_link_payment(order, "pi_link", %{amount_paid: order.grand_total},
          actor: Edenflowers.Actors.system_actor()
        )

      refute has_element?(view, "#still-owed")
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
