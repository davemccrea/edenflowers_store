defmodule EdenflowersWeb.Admin.SearchLiveTest do
  # Not async: the page refreshes on admin-wide broadcasts, which other tests running beside it
  # also send, and a refresh landing mid-search would make these assertions race.
  use EdenflowersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Generator

  alias Edenflowers.Orders

  setup :log_in_admin

  test "finds orders and customers from one search", %{conn: conn} do
    customer = generate(admin_user(admin: false, name: "Ada Byron", email: "ada@example.com"))

    order =
      generate(
        order(
          state: :placed,
          customer_name: "Ada Lovelace",
          user_id: customer.id,
          fulfillment_method: :pickup,
          fulfillment_date: ~D[2026-06-10],
          fulfillment_status: :pending,
          grand_total: "42.00",
          ordered_at: DateTime.utc_now()
        )
      )

    generate(admin_user(admin: false, name: "Grace Hopper", email: "grace@example.com"))

    {:ok, view, _html} = live(conn, ~p"/admin/search?q=ada")
    render_async(view)

    assert has_element?(view, ~s|#search-orders a[href="/admin/orders/#{order.id}"]|, "Ada Lovelace")
    assert has_element?(view, ~s|#search-customers a[href="/admin/customers/#{customer.id}"]|, "Ada Byron")
    refute render(view) =~ "Grace Hopper"
  end

  test "shows an order that has no reference number", %{conn: conn} do
    order =
      generate(
        order(
          state: :placed,
          customer_name: "Ada Lovelace",
          order_reference: nil,
          fulfillment_method: :pickup,
          fulfillment_status: :pending,
          grand_total: "42.00",
          ordered_at: DateTime.utc_now()
        )
      )

    {:ok, view, _html} = live(conn, ~p"/admin/search?q=ada")
    render_async(view)

    assert has_element?(view, ~s|#search-orders a[href="/admin/orders/#{order.id}"]|, "Ada Lovelace")
  end

  test "finds a promotion by part of its code, any case", %{conn: conn} do
    promotion = generate(promotion(code: "SPRING26", name: "Spring sale"))
    generate(promotion(code: "AUTUMN26", name: "Spring leftovers"))

    {:ok, view, _html} = live(conn, ~p"/admin/search?q=spring")
    render_async(view)

    assert has_element?(view, ~s|#search-promotions a[href="/admin/promotions/#{promotion.id}"]|, "SPRING26")
    refute has_element?(view, "#search-promotions", "AUTUMN26")
  end

  test "finds a subscription, a course booking and its course", %{conn: conn} do
    subscriber = generate(admin_user(admin: false, name: "Ada Byron", email: "byron@example.com"))
    subscription = generate(subscription(user_id: subscriber.id))
    course = generate(course(name: "Adas kranskurs"))
    booking = generate(course_registration(course_id: course.id, name: "Ada Lovelace", status: :confirmed))
    generate(course_registration(course_id: course.id, name: "Ada Unfinished", status: :pending))

    {:ok, view, _html} = live(conn, ~p"/admin/search?q=ada")
    render_async(view)

    assert has_element?(view, ~s|#search-subscriptions a[href="/admin/subscriptions/#{subscription.id}"]|, "Ada Byron")
    assert has_element?(view, ~s|#search-courses a[href="/admin/courses/#{course.id}"]|, "Adas kranskurs")

    assert has_element?(
             view,
             ~s|#search-bookings a[href="/admin/courses/#{course.id}?booking=#{booking.id}"]|,
             "Ada Lovelace"
           )

    # An unfinished website checkout holds no place, so it isn't a booking to find.
    refute has_element?(view, "#search-bookings", "Ada Unfinished")
  end

  test "finds an invoice by its customer", %{conn: conn, admin: admin} do
    invoice = Edenflowers.Payments.create_invoice!(%{buyer_name: "Ada Lovelace"}, actor: admin)

    {:ok, view, _html} = live(conn, ~p"/admin/search?q=lovelace")
    render_async(view)

    assert has_element?(view, ~s|#search-invoices a[href="/admin/invoices/#{invoice.id}"]|, "Ada Lovelace")
  end

  test "shows a skeleton until the results arrive", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/admin/search?q=ada")

    assert html =~ ~s(id="search-loading")
    render_async(view)
    refute has_element?(view, "#search-loading")
  end

  test "says when nothing matches, and before anything is searched", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/search?q=zzzqqq")
    render_async(view)
    assert has_element?(view, "#search-empty", "No results for “zzzqqq”")

    {:ok, view, _html} = live(conn, ~p"/admin/search")
    assert has_element?(view, "#search-empty", "Nothing searched yet")
  end

  test "refreshes results when a matching order is placed elsewhere", %{conn: conn, admin: admin} do
    {:ok, view, _html} = live(conn, ~p"/admin/search?q=ada")
    render_async(view)
    refute render(view) =~ "Ada Lovelace"

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

    Orders.update_florist_note!(order, %{florist_note: "White only"}, actor: admin)
    Process.sleep(200)
    render_async(view)

    assert has_element?(view, ~s|#search-orders a[href="/admin/orders/#{order.id}"]|, "Ada Lovelace")
  end

  test "the admin header searches without leaving the live session", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/admin")

    # The plain form still works before LiveView connects.
    assert html =~ ~s(action="/admin/search")

    view |> element("#admin-search-form") |> render_submit(%{q: "ada"})
    assert_redirect(view, ~p"/admin/search?q=ada")
  end
end
