defmodule EdenflowersWeb.Admin.EditorNoticeTest do
  use EdenflowersWeb.ConnCase, async: false

  import Generator
  import Phoenix.LiveViewTest

  setup :log_in_admin

  test "refused readiness actions retain the warning and unfinished note", %{conn: conn, admin: admin} do
    order = placed_order()
    {:ok, view, _} = live(conn, ~p"/admin/orders/#{order.id}")
    view |> form("#florist-note-form", note: %{florist_note: "Keep my draft"}) |> render_change()
    Edenflowers.Orders.mark_order_ready!(order, actor: admin)
    assert has_element?(view, "#editor-stale-notice")

    render_click(view, "mark_ready")

    assert has_element?(view, "#flash-error", "The order has changed")
    assert has_element?(view, "#editor-stale-notice")
    assert has_element?(view, "#florist-note-form textarea", "Keep my draft")
    assert has_element?(view, "button", "Mark as ready")
  end

  test "subscription pricing dependencies warn without changing open choices", %{conn: conn, admin: admin} do
    subscription = generate(subscription())
    {:ok, view, _} = live(conn, ~p"/admin/subscriptions/#{subscription.id}")
    render_click(view, "open_change")
    choices = view |> element("#change-subscription-form select[name='change[product_variant_id]']") |> render()
    variant = Ash.get!(Edenflowers.Catalog.ProductVariant, subscription.product_variant_id, actor: admin)
    Ash.update!(variant, %{price: Decimal.add(variant.price, 10)}, actor: admin)

    assert has_element?(view, "#editor-stale-notice")
    assert view |> element("#change-subscription-form select[name='change[product_variant_id]']") |> render() == choices
  end

  test "successful appearance saves clear external warnings", %{conn: conn, admin: admin} do
    {:ok, view, _} = live(conn, ~p"/admin/account")
    Edenflowers.Accounts.update_admin_appearance!(admin, %{admin_hue: 180}, actor: admin)
    assert has_element?(view, "#editor-stale-notice")

    render_click(view, "update_appearance", %{"admin_hue" => "190"})

    refute has_element?(view, "#editor-stale-notice")
  end

  test "successfully cancelling a booking clears an external-save warning", %{conn: conn, admin: admin} do
    course = generate(course())
    registration = generate(course_registration(course_id: course.id, status: :confirmed))
    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}")
    Ash.update!(course, %{name: "Changed elsewhere"}, action: :update, actor: admin)
    assert has_element?(view, "#editor-stale-notice")

    view |> element(~s|button[phx-click="open_cancel"][phx-value-id="#{registration.id}"]|) |> render_click()
    view |> form("#cancel-form", cancel: %{email_customer?: "false"}) |> render_submit()

    assert Ash.reload!(registration, actor: admin).status == :cancelled
    refute has_element?(view, "#editor-stale-notice")
  end

  test "successful settlement clears a warning but failed settlement does not", %{conn: conn, admin: admin} do
    course = generate(course())
    registration = generate(course_registration(course_id: course.id, status: :confirmed, amount: Decimal.new("50")))
    {:ok, view, _html} = live(conn, ~p"/admin/courses/#{course.id}")
    view |> element("#settle-#{registration.id}") |> render_click()
    Ash.update!(course, %{name: "Changed elsewhere"}, action: :update, actor: admin)
    assert has_element?(view, "#editor-stale-notice")

    view
    |> form("#payment-#{registration.id}-form", payment: %{amount: "-1", payment_method: "cash"})
    |> render_submit()

    assert has_element?(view, "#editor-stale-notice")

    view
    |> form("#payment-#{registration.id}-form",
      payment: %{amount: "50", payment_method: "cash", email_receipt?: "false"}
    )
    |> render_submit()

    fresh = Ash.reload!(registration, load: [:amount_paid], actor: admin)
    assert Decimal.eq?(fresh.amount_paid, 50)
    refute has_element?(view, "#editor-stale-notice")
  end

  test "record editors warn even before input and reload to their own route", %{conn: conn, admin: admin} do
    course = generate(course())
    promotion = generate(promotion())
    order = placed_order()
    option = generate(fulfillment_option())
    calendar = Edenflowers.Fulfillment.get_shop_calendar!(actor: admin)

    for {path, record, action, params} <- [
          {~p"/admin/courses/#{course.id}/edit", course, :update, %{name: "Changed course"}},
          {~p"/admin/courses/#{course.id}", course, :update, %{name: "Changed detail"}},
          {~p"/admin/courses/#{course.id}/bookings/new", course, :update, %{name: "Changed again"}},
          {~p"/admin/promotions/#{promotion.id}", promotion, :update, %{name: "Changed promotion"}},
          {~p"/admin/orders/#{order.id}/edit", order, :update_florist_note, %{florist_note: "Changed note"}},
          {~p"/admin/fulfillments/#{option.id}", option, :update_pricing, %{base_price: "7"}},
          {~p"/admin/fulfillments", calendar, :update_same_day, %{same_day: false}},
          {~p"/admin/orders/new", calendar, :update_same_day, %{same_day: false}},
          {~p"/admin/account", admin, :update_admin_appearance, %{admin_hue: 200}}
        ] do
      {:ok, view, _} = live(conn, path)
      refute has_element?(view, "#editor-stale-notice")

      Ash.update!(record, params, action: action, actor: admin)

      assert has_element?(view, "#editor-stale-notice[role=alert]", "Saving now may overwrite")
      view |> element("#editor-stale-notice button") |> render_click()
      assert_redirect(view, path)
      {:ok, reloaded, _} = live(conn, path)
      refute has_element?(reloaded, "#editor-stale-notice")
    end
  end

  test "a course editor can save despite an external save", %{conn: conn, admin: admin} do
    course = generate(course(name: "Original course"))
    {:ok, view, _} = live(conn, ~p"/admin/courses/#{course.id}/edit")
    Ash.update!(course, %{name: "Changed elsewhere"}, action: :update, actor: admin)
    assert has_element?(view, "#editor-stale-notice")

    view |> form("#course-form", form: %{name: "Save anyway"}) |> render_submit()
    assert_redirect(view, ~p"/admin/courses/#{course.id}/edit")
    assert Ash.reload!(course, actor: admin).name == "Save anyway"
  end

  test "account changes publish warnings but the editor's own appearance save does not", %{conn: conn, admin: admin} do
    {:ok, view, _} = live(conn, ~p"/admin/account")
    render_hook(view, "update_appearance", %{"admin_hue" => 325})
    refute has_element?(view, "#editor-stale-notice")

    Edenflowers.Accounts.update_admin_appearance!(admin, %{admin_hue: 200}, actor: admin)
    assert has_element?(view, "#editor-stale-notice")
  end
end
