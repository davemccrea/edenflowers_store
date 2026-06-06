defmodule EdenflowersWeb.Admin.OrderDetailLiveTest do
  use EdenflowersWeb.ConnCase, async: false

  import Generator
  import Phoenix.LiveViewTest

  alias AshAuthentication.Jwt
  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.Store.Order

  setup %{conn: conn} do
    admin = generate(admin_user()) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(admin)

    %{conn: conn, admin: admin}
  end

  test "renders a placed order detail page", %{conn: conn} do
    order = placed_order()

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, "h1", order.order_reference)
    assert has_element?(view, "header", "Ada Lovelace")
    assert has_element?(view, "header", "Payment")
    assert has_element?(view, "header", "Fulfillment")
    assert has_element?(view, "#order-fulfillment-summary", "Pickup")
    assert has_element?(view, "#order-fulfillment-summary", "2026")
    assert has_element?(view, "#order-customer", "Ada Lovelace")
    assert has_element?(view, "#order-customer", "ada@example.com")
    assert has_element?(view, ~s|#order-customer a[href^="https://app.fastmail.com/mail/search:"]|)
    assert has_element?(view, "#order-timeline", "Order placed")
    assert has_element?(view, "#order-payment-summary", "View payment in Stripe")
    refute has_element?(view, "#order-technical-details")
    assert has_element?(view, ~s|button[phx-click="mark_fulfilled"]|)
  end

  test "marking an order fulfilled flips the status and shows the fulfilled badge", %{conn: conn} do
    order = placed_order()

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    view
    |> element(~s|button[phx-click="mark_fulfilled"]|)
    |> render_click()

    refute has_element?(view, ~s|button[phx-click="mark_fulfilled"]|)
    assert has_element?(view, ".badge-success", "Fulfilled")

    reloaded = Order.get_for_admin!(order.id, actor: %{admin: true})
    assert reloaded.fulfillment_status == :fulfilled
  end

  test "shows customer and recipient as separate sections for a gift order", %{conn: conn} do
    order =
      placed_order(
        gift: true,
        recipient_name: "Grace Hopper",
        recipient_phone_number: "040 123 4567"
      )

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, "#order-customer", "Ada Lovelace")
    assert has_element?(view, "#order-recipient", "Grace Hopper")
    assert has_element?(view, ~s|#order-recipient a[href="tel:040 123 4567"]|)
    assert has_element?(view, "#order-fulfillment-summary", "Pickup")
    # Gift is also surfaced prominently in the header, matching the dashboard.
    assert has_element?(view, "header", "Grace Hopper")
  end

  test "timeline reflects a refunded payment as a received-but-refunded state", %{conn: conn} do
    order = placed_order(payment_status: :refunded)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, "#order-timeline", "Refunded")
  end

  test "shows the phone under customer and omits recipient for a non-gift order", %{conn: conn} do
    order = placed_order(recipient_phone_number: "040 123 4567")

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, "#order-customer", "Customer")
    assert has_element?(view, ~s|#order-customer a[href="tel:040 123 4567"]|)
    refute has_element?(view, "#order-recipient")
  end

  test "offers a directions link for a delivery order even without geocoded coordinates", %{conn: conn} do
    order =
      placed_order(
        fulfillment_method: :delivery,
        delivery_address: "Kauppapuistikko 20, 65100 Vaasa",
        position: nil
      )

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(
             view,
             "#order-fulfillment-summary a[href*='maps/dir'][href*='travelmode=driving']",
             "Get directions"
           )
  end

  test "uses driving directions for a geocoded delivery order", %{conn: conn} do
    order =
      placed_order(
        fulfillment_method: :delivery,
        delivery_address: "Kauppapuistikko 20, 65100 Vaasa",
        position: "63.0951,21.6165"
      )

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(
             view,
             "#order-fulfillment-summary a[href*='destination=63.0951%2C21.6165'][href*='travelmode=driving']"
           )
  end

  test "redirects missing orders back to the admin orders table", %{conn: conn} do
    missing_id = Ash.UUID.generate()

    assert {:error, {:live_redirect, %{to: "/admin/orders"}}} = live(conn, ~p"/admin/orders/#{missing_id}")
  end

  test "reschedules an eligible delivery order to a new date", %{conn: conn} do
    order = placed_order(fulfillment_method: :delivery, position: "63.1,21.6", fulfillment_date: ~D[2026-06-10])

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, "button[phx-click=toggle_reschedule]")

    view |> element("button[phx-click=toggle_reschedule]") |> render_click()

    view
    |> form("form[phx-submit=reschedule]", %{fulfillment_date: "2026-06-20"})
    |> render_submit()

    assert Order.get_by_id!(order.id, authorize?: false).fulfillment_date == ~D[2026-06-20]
  end

  test "does not offer rescheduling for a pickup order", %{conn: conn} do
    order = placed_order(fulfillment_method: :pickup)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    refute has_element?(view, "button[phx-click=toggle_reschedule]")
  end

  test "shows delivery attempt history", %{conn: conn} do
    order = placed_order(fulfillment_method: :delivery, position: "63.1,21.6")
    record_failed_attempt(order)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, "h2", "Delivery attempts")
    assert render(view) =~ "Recipient unavailable"
  end

  defp record_failed_attempt(order) do
    system = %{system: true}
    driver = generate(driver())
    admin = generate(admin_user())

    route =
      Ash.create!(Edenflowers.Store.DeliveryRoute, %{delivery_date: ~D[2026-06-09], driver_id: driver.id},
        action: :create,
        actor: system
      )

    batch =
      Ash.create!(
        Edenflowers.Store.DeliveryBatch,
        %{delivery_date: ~D[2026-06-09], published_by_user_id: admin.id, published_at: DateTime.utc_now()},
        action: :create,
        actor: system
      )

    trip =
      Ash.create!(
        Edenflowers.Store.DeliveryTrip,
        %{
          delivery_route_id: route.id,
          batch_id: batch.id,
          sequence: 1,
          distance: 1,
          driving_duration: 1,
          service_duration: 1,
          published_at: DateTime.utc_now()
        },
        action: :create,
        actor: system
      )

    stop =
      Ash.create!(
        Edenflowers.Store.DeliveryStop,
        %{delivery_trip_id: trip.id, order_id: order.id, sequence: 1, leg_distance: 1, leg_duration: 1},
        action: :create,
        actor: system
      )

    Ash.create!(
      Edenflowers.Store.DeliveryAttempt,
      %{
        delivery_stop_id: stop.id,
        outcome: :failed,
        failure_reason: :recipient_unavailable,
        recorded_at: DateTime.utc_now(),
        actor_kind: :driver_link
      },
      action: :create,
      actor: system
    )
  end

  defp placed_order(overrides \\ []) do
    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    variant = generate(product_variant(product_id: product.id, price: "42.00"))
    fulfillment = generate(fulfillment_option(tax_rate_id: tax_rate.id, name: "Pickup"))

    attrs =
      Keyword.merge(
        [
          state: :placed,
          order_reference: "EF-DETAIL",
          customer_name: "Ada Lovelace",
          customer_email: "ada@example.com",
          fulfillment_option_id: fulfillment.id,
          fulfillment_option_name: "Pickup",
          fulfillment_method: :pickup,
          fulfillment_date: ~D[2026-06-10],
          fulfillment_fee: "4.50",
          fulfillment_tax_percentage: tax_rate.percentage,
          payment_status: :paid,
          fulfillment_status: :pending,
          payment_intent_id: "pi_test_order_detail",
          ordered_at: DateTime.utc_now(),
          locale: "en-GB"
        ],
        overrides
      )

    order = generate(order(attrs))

    generate(line_item(order_id: order.id, product_variant_id: variant.id, quantity: 2))
    order
  end

  defp with_token(user) do
    {:ok, token, _claims} = Jwt.token_for_user(user)
    %{user | __metadata__: Map.put(user.__metadata__ || %{}, :token, token)}
  end
end
