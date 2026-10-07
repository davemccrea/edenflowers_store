defmodule EdenflowersWeb.Admin.OrderDetailLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.Orders

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
    generate(payment(order_id: order.id, amount: Decimal.new("46.50"), payment_intent_id: "pi_test_order_detail"))

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, "h1", "Ada Lovelace")
    assert has_element?(view, "header", order.order_reference)
    assert has_element?(view, "header", "Payment")
    refute has_element?(view, "header", "Fulfillment")
    assert has_element?(view, "#order-fulfillment-summary", "Pickup")

    assert has_element?(
             view,
             "#order-fulfillment-summary",
             Edenflowers.Format.weekday_day_month(order.fulfillment_date, "en-GB")
           )

    refute has_element?(view, "#order-customer", "Ada Lovelace")
    assert has_element?(view, "#order-customer", "ada@example.com")
    assert has_element?(view, ~s|#order-customer a[href^="https://app.fastmail.com/mail/search:"]|)
    assert has_element?(view, ~s|#order-payments a[aria-label="View €46.50 payment in Stripe"]|)
    assert has_element?(view, "#order-payment-summary dt", "2 ×")
    refute has_element?(view, "#order-items", "€42.00")
    refute has_element?(view, ~s|header a[href="/order/#{order.id}/receipt"]|)
    refute has_element?(view, "#order-technical-details")
    assert has_element?(view, ~s|button[phx-click="mark_fulfilled"]|)
    assert has_element?(view, ~s|header a[href="#order-payment-summary"]|, "To collect")
  end

  test "the actions menu says why each action is unavailable", %{conn: conn} do
    order = placed_order(customer_email: nil, customer_phone_number: "044 222 3344", fulfillment_status: :fulfilled)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, ~s|button[aria-label="More actions"]|)
    assert has_element?(view, ".menu-disabled", "No email address")
    assert has_element?(view, ".menu-disabled", "Not paid")
    assert has_element?(view, ".menu-disabled", "Already fulfilled")
    refute has_element?(view, ~s|button[phx-click="cancel_order"]|)
    refute has_element?(view, ~s|button[phx-click="fetch_stripe_refunds"]|)
  end

  @tag :typst
  test "opens the receipt of another customer's order", %{conn: conn} do
    order = placed_order(payment_status: :paid)

    assert "%PDF" <> _ = conn |> get(~p"/order/#{order.id}/receipt") |> response(200)
  end

  test "payment summary subtracts the discount once", %{conn: conn} do
    promotion = generate(promotion(discount_rate: "0.20", minimum_cart_total: "0"))

    order =
      placed_order(
        promotion_id: promotion.id,
        promotion_name: promotion.name,
        promotion_code: promotion.code,
        discount_rate: promotion.discount_rate
      )

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, "#order-payment-summary", "€84.00")
    assert has_element?(view, "#order-payment-summary", "-€16.80")
    assert has_element?(view, "#order-payment-summary", "€71.70")
  end

  test "capitalizes the today badge", %{conn: conn} do
    today = DateTime.now!("Europe/Helsinki") |> DateTime.to_date()
    order = placed_order(fulfillment_date: today)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, ".admin-badge-success", "Today")
  end

  test "marking an order fulfilled flips the status and shows the fulfilled badge", %{conn: conn} do
    order = placed_order()

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    view
    |> element(~s|button[phx-click="mark_fulfilled"]|)
    |> render_click()

    refute has_element?(view, ~s|button[phx-click="mark_fulfilled"]|)
    assert has_element?(view, ".badge-success", "Fulfilled")

    reloaded = Orders.get_order_for_admin!(order.id, actor: %{admin: true})
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

    assert has_element?(view, "#order-recipient", "Grace Hopper")
    # The buyer collects a gift pickup, so the number is theirs.
    assert has_element?(view, ~s|#order-customer a[href="tel:040 123 4567"]|)
    refute has_element?(view, ~s|#order-recipient a[href^="tel:"]|)
    assert has_element?(view, "#order-fulfillment-summary", "Pickup")
    # Gift is also surfaced prominently in the header, matching the dashboard.
    assert has_element?(view, "header", "Grace Hopper")
  end

  test "shows the phone under the recipient for a gift delivery", %{conn: conn} do
    order =
      placed_order(
        gift: true,
        recipient_name: "Grace Hopper",
        recipient_phone_number: "040 123 4567",
        fulfillment_method: :delivery,
        delivery_address: "Kauppapuistikko 20, 65100 Vaasa"
      )

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, ~s|#order-recipient a[href="tel:040 123 4567"]|)
    refute has_element?(view, ~s|#order-customer a[href^="tel:"]|)
  end

  test "header shows a refunded payment", %{conn: conn} do
    order = placed_order(payment_status: :refunded)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, "header", "Refunded")
  end

  test "logs payments and refunds with their amounts", %{conn: conn} do
    order = placed_order()
    generate(payment(order_id: order.id, amount: Decimal.new("46.50")))
    generate(payment(order_id: order.id, amount: Decimal.new("-10.00"), method: :cash))

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, "#order-log", "Paid €46.50 · Online (Stripe)")
    assert has_element?(view, "#order-log", "Refunded €10.00 · Cash")
  end

  test "fetches a refund from Stripe whose webhook never arrived", %{conn: conn} do
    order = placed_order()
    generate(payment(order_id: order.id, amount: Decimal.new("46.50"), payment_intent_id: "pi_missed_refund"))

    Mox.expect(Edenflowers.External.StripeAPI.Mock, :list_refunds, 2, fn "pi_missed_refund" ->
      {:ok, [%{id: "re_missed", payment_intent: "pi_missed_refund", amount: 1000, status: "succeeded"}]}
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    view |> element(~s|button[phx-click="fetch_stripe_refunds"]|) |> render_click()
    assert has_element?(view, "#order-log", "Refunded €10.00 · Online (Stripe)")

    assert view |> element(~s|button[phx-click="fetch_stripe_refunds"]|) |> render_click() =~
             "No new refunds in Stripe."
  end

  test "refunds the balance through Stripe, newest payment first, as far as each still covers", %{conn: conn} do
    order = placed_order()

    generate(
      payment(
        order_id: order.id,
        amount: Decimal.new("200.00"),
        payment_intent_id: "pi_old",
        paid_at: ~U[2026-06-01 10:00:00Z]
      )
    )

    generate(
      payment(
        order_id: order.id,
        amount: Decimal.new("30.00"),
        payment_intent_id: "pi_new",
        paid_at: ~U[2026-06-02 10:00:00Z]
      )
    )

    balance = Orders.get_order_for_admin!(order.id, authorize?: false).balance
    to_refund = Edenflowers.External.StripeAPI.to_stripe_amount(Decimal.abs(balance))
    test_pid = self()

    Edenflowers.External.StripeAPI.Mock
    |> Mox.stub(:list_refunds, fn
      "pi_new" -> {:ok, [%{id: "re_pending", amount: 1000, status: "pending"}]}
      "pi_old" -> {:ok, []}
    end)
    |> Mox.expect(:create_refund, 2, fn payment_intent_id, cents, _key ->
      send(test_pid, {:refunded, payment_intent_id, cents})
      {:ok, %{id: "re_#{payment_intent_id}", payment_intent: payment_intent_id, amount: cents, status: "succeeded"}}
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    view |> element(~s|button[phx-click="refund_with_stripe"]|) |> render_click()

    # The pending €10 on pi_new is already on its way, so it comes off what's owed.
    assert_received {:refunded, "pi_new", 2000}
    assert_received {:refunded, "pi_old", rest} when rest == to_refund - 1000 - 2000
  end

  test "doesn't refund again what Stripe already has refunds for", %{conn: conn} do
    order = placed_order()
    generate(payment(order_id: order.id, amount: Decimal.new("500.00"), payment_intent_id: "pi_paid"))

    balance = Orders.get_order_for_admin!(order.id, authorize?: false).balance
    pending = Edenflowers.External.StripeAPI.to_stripe_amount(Decimal.abs(balance)) - 1000

    Edenflowers.External.StripeAPI.Mock
    |> Mox.stub(:list_refunds, fn "pi_paid" ->
      {:ok,
       [
         %{id: "re_missed", payment_intent: "pi_paid", amount: 1000, status: "succeeded"},
         %{id: "re_pending", payment_intent: "pi_paid", amount: pending, status: "pending"}
       ]}
    end)
    |> Mox.expect(:create_refund, 0, fn _, _, _ -> flunk("refunded twice") end)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert view |> element(~s|button[phx-click="refund_with_stripe"]|) |> render_click() =~
             "Nothing left to refund."

    assert has_element?(view, "#order-log", "Refunded €10.00 · Online (Stripe)")
  end

  test "offers no Stripe refund when the order wasn't paid through Stripe", %{conn: conn} do
    order = placed_order(payment_intent_id: nil)
    generate(payment(order_id: order.id, amount: Decimal.new("200.00"), method: :cash))

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, "#order-collect", "To refund")
    refute has_element?(view, ~s|button[phx-click="refund_with_stripe"]|)
  end

  test "shows the phone under customer and omits recipient for a non-gift order", %{conn: conn} do
    order = placed_order(recipient_phone_number: "040 123 4567")

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, "#order-customer", "Customer")
    assert has_element?(view, ~s|#order-customer a[href="tel:040 123 4567"]|)
    refute has_element?(view, "#order-recipient")
  end

  test "offers ready-for-pickup message links in the customer's language", %{conn: conn} do
    order = placed_order(recipient_phone_number: "040 123 4567", locale: "sv-FI")

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    body = "Hej%20Ada%2C%20din%20best%C3%A4llning%20DETAIL"
    assert has_element?(view, ~s|#order-customer a[href^="sms:+358401234567?&body=#{body}"]|)
    assert has_element?(view, ~s|#order-customer a[href^="https://wa.me/358401234567?text=#{body}"]|)
  end

  test "omits ready-for-pickup links for deliveries and fulfilled pickups", %{conn: conn} do
    delivery =
      placed_order(
        recipient_phone_number: "040 123 4567",
        fulfillment_method: :delivery,
        delivery_address: "Kauppapuistikko 20, 65100 Vaasa"
      )

    fulfilled =
      placed_order(
        order_reference: "FULFILLED",
        recipient_phone_number: "040 123 4567",
        fulfillment_status: :fulfilled
      )

    for order <- [delivery, fulfilled] do
      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
      refute has_element?(view, ~s|a[href^="sms:"]|)
    end
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
             "#order-directions a[href*='maps/dir'][href*='travelmode=driving']",
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
             "#order-directions a[href*='destination=63.0951%2C21.6165'][href*='travelmode=driving']"
           )
  end

  test "steps through the orders still to fulfil by fulfillment date", %{conn: conn} do
    later = placed_order(order_reference: "LATER", fulfillment_date: ~D[2026-06-12])
    current = placed_order(order_reference: "CURRENT", fulfillment_date: ~D[2026-06-11])
    earlier = placed_order(order_reference: "EARLIER", fulfillment_date: ~D[2026-06-10])
    placed_order(order_reference: "DONE", fulfillment_date: ~D[2026-06-11], fulfillment_status: :fulfilled)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{current.id}")

    assert has_element?(view, "header nav", "2 of 3 to fulfil")
    assert has_element?(view, ~s|header nav a[href="/admin/orders/#{earlier.id}"]|)
    assert has_element?(view, ~s|header nav a[href="/admin/orders/#{later.id}"]|)
  end

  test "keeps stepping after marking an order fulfilled and counts what is left", %{conn: conn} do
    current = placed_order(order_reference: "CURRENT", fulfillment_date: ~D[2026-06-11])
    later = placed_order(order_reference: "LATER", fulfillment_date: ~D[2026-06-12])
    placed_order(order_reference: "LATEST", fulfillment_date: ~D[2026-06-13])

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{current.id}")

    view
    |> element(~s|button[phx-click="mark_fulfilled"]|)
    |> render_click()

    assert has_element?(view, "header nav", "Fulfilled · 2 left")
    refute has_element?(view, "header nav", "1 of 3 to fulfil")
    assert has_element?(view, ~s|header nav a[href="/admin/orders/#{later.id}"]|)
  end

  test "omits queue stepping for an order already fulfilled", %{conn: conn} do
    order = placed_order(fulfillment_status: :fulfilled)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    refute has_element?(view, "header nav")
  end

  test "redirects missing orders back to the admin orders table", %{conn: conn} do
    missing_id = Ash.UUID.generate()

    assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/admin/orders/#{missing_id}")
    assert to == ~p"/admin/orders"
  end

  defp placed_order(overrides \\ []) do
    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    variant = generate(product_variant(product_id: product.id, price: "42.00"))
    fulfillment = generate(fulfillment_option(tax_rate_id: tax_rate.id))

    {payment_status, overrides} = Keyword.pop(overrides, :payment_status, :pending)

    attrs =
      Keyword.merge(
        [
          state: :placed,
          order_reference: "DETAIL",
          customer_name: "Ada Lovelace",
          customer_email: "ada@example.com",
          fulfillment_option_id: fulfillment.id,
          fulfillment_option_name: "Pickup",
          fulfillment_method: :pickup,
          fulfillment_date: ~D[2026-06-10],
          fulfillment_fee: "4.50",
          fulfillment_tax_rate: tax_rate.percentage,
          fulfillment_status: :pending,
          payment_intent_id: "pi_test_order_detail",
          ordered_at: DateTime.utc_now(),
          locale: "en-GB"
        ],
        overrides
      )

    order = generate(order(attrs))

    generate(line_item(order_id: order.id, product_variant_id: variant.id, quantity: 2))
    order = Ash.load!(order, :grand_total, authorize?: false)

    if payment_status in [:paid, :refunded],
      do: generate(payment(order_id: order.id, amount: order.grand_total))

    if payment_status == :refunded,
      do: generate(payment(order_id: order.id, amount: Decimal.negate(order.grand_total)))

    Ash.load!(order, :payment_status, authorize?: false, reuse_values?: false)
  end
end
