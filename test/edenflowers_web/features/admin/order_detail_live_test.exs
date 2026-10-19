defmodule EdenflowersWeb.Admin.OrderDetailLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  use Oban.Testing, repo: Edenflowers.Repo

  import Generator
  import Phoenix.LiveViewTest

  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.External.StripeAPI
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
    assert has_element?(view, ~s|header a[href="/admin/orders"]|, "Orders")
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
    assert has_element?(view, ~s|button[phx-click="confirm_fulfillment"]|)
    assert has_element?(view, ~s|header a[href="#order-payment-summary"]|, "To collect")
  end

  test "warns when a delivery has no phone to call", %{conn: conn} do
    missing = placed_order(fulfillment_method: :delivery, gift: true, recipient_name: "Grandma")
    phoned = placed_order(fulfillment_method: :delivery, recipient_phone_number: "+358401234567")

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{missing.id}")
    assert has_element?(view, "#order-missing-phone", "Missing recipient phone")

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{phoned.id}")
    refute has_element?(view, "#order-missing-phone")
  end

  test "an unpaid custom order can be deleted, an online one can't", %{conn: conn} do
    custom = placed_order(origin: :custom, payment_intent_id: nil)
    online = placed_order()

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{online.id}")
    refute has_element?(view, ~s|button[phx-click="delete_order"]|)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{custom.id}")
    assert has_element?(view, ~s|button[phx-click="delete_order"][data-confirm]|, "Delete order")

    assert {:error, {:live_redirect, %{to: "/admin/orders"}}} =
             view |> element(~s|button[phx-click="delete_order"]|) |> render_click()

    assert {:error, _} = Orders.get_order_by_id(custom.id, authorize?: false)
  end

  test "a custom order with a payment can't be deleted", %{conn: conn, admin: admin} do
    order = placed_order(origin: :custom, payment_intent_id: nil)
    {:ok, _order} = Orders.record_payment(order, "1.00", :cash, actor: admin)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    refute has_element?(view, ~s|button[phx-click="delete_order"]|)
  end

  test "the actions menu offers the order details until paid, then the receipt", %{conn: conn} do
    order = placed_order()

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, ~s|button[phx-click="send_order_details"]|)
    refute has_element?(view, "li", "Email receipt")

    order = Ash.load!(order, :grand_total, authorize?: false)
    generate(payment(order_id: order.id, amount: order.grand_total, payment_intent_id: "pi_test_menu_paid"))

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, ~s|button[phx-click="email_receipt"]|, "Email receipt")
    refute has_element?(view, "li", "Email order details")

    Ash.Seed.update!(order, %{receipt_emailed_at: DateTime.utc_now()})

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, ~s|button[phx-click="email_receipt"]|, "Resend receipt")
    assert has_element?(view, ~s|button[phx-click="email_receipt"][data-confirm^="Last sent "]|)
  end

  test "the payment link button says Resend once the link has been emailed", %{conn: conn} do
    order = placed_order()

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
    assert has_element?(view, ~s|button[phx-click="email_payment_link"]|, "Email payment link")
    assert has_element?(view, ~s|button[phx-click="email_payment_link"][data-confirm^="Email a payment link"]|)

    Ash.Seed.update!(order, %{payment_link_token: "tok_resend_label", details_emailed_at: DateTime.utc_now()})

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
    assert has_element?(view, ~s|button[phx-click="email_payment_link"]|, "Resend payment link")
  end

  test "the actions menu says why each action is unavailable", %{conn: conn} do
    order = placed_order(customer_email: nil, customer_phone_number: "044 222 3344", fulfillment_status: :fulfilled)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, ~s|button[aria-label="More actions"]|)
    assert has_element?(view, "[aria-disabled=true]", "No email address")
    assert has_element?(view, "[aria-disabled=true]", "Not paid")
    assert has_element?(view, "[aria-disabled=true]", "Already fulfilled")
    refute has_element?(view, ~s|button[phx-click="cancel_order"]|)
    refute has_element?(view, ~s|button[phx-click="fetch_stripe_refunds"]|)
  end

  @tag :typst
  test "opens the receipt of another customer's order", %{conn: conn} do
    order = placed_order(paid: true)

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
    today = Edenflowers.ShopTime.today()
    order = placed_order(fulfillment_date: today)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, "#order-fulfillment-summary", "Today")
  end

  test "marking an order fulfilled flips the status and shows the fulfilled badge", %{conn: conn} do
    order = placed_order()

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    view
    |> element(~s|button[phx-click="confirm_fulfillment"]|)
    |> render_click()

    view |> form("#confirm-fulfillment-form") |> render_submit()

    refute has_element?(view, ~s|button[phx-click="confirm_fulfillment"]|)
    assert has_element?(view, "#order-status", "Fulfilled")
    assert render(view) =~ "Order marked as collected. Confirmation queued."

    reloaded = Orders.get_order_for_admin!(order.id, actor: %{admin: true})
    assert reloaded.fulfillment_status == :fulfilled
  end

  test "fulfills a pickup with no customer email", %{conn: conn} do
    order = placed_order(customer_email: nil, customer_phone_number: "044 222 3344")

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
    view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
    refute has_element?(view, ~s|#confirm-fulfillment-form input[type="checkbox"]|)
    assert has_element?(view, "#confirm-fulfillment-form", "No confirmation will be emailed")
    view |> form("#confirm-fulfillment-form") |> render_submit()

    assert has_element?(view, "#order-status", "Fulfilled")
    assert Orders.get_order_for_admin!(order.id, actor: %{admin: true}).fulfillment_status == :fulfilled
    refute_enqueued(worker: Edenflowers.Orders.Workers.SendDeliveredEmail)
  end

  test "emails the confirmation from the menu and logs it when sent", %{conn: conn} do
    order = placed_order(fulfillment_status: :fulfilled)
    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    view |> element(~s|button[phx-click="email_fulfillment_confirmation"]|, "Email confirmation") |> render_click()
    assert render(view) =~ "Confirmation queued."
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :default)

    assert has_element?(view, "#order-log li", ~r/Fulfillment confirmation emailed.*ada@example\.com/s)
    assert has_element?(view, ~s|button[phx-click="email_fulfillment_confirmation"]|, "Resend confirmation")
  end

  @tag capture_log: true
  test "an open page shows a confirmation that failed in the background", %{conn: conn} do
    Req.Test.stub(Edenflowers.Orders.Changes.SendDeliveredEmail, fn conn ->
      Plug.Conn.send_resp(conn, 503, "unavailable")
    end)

    order =
      placed_order(
        fulfillment_method: :delivery,
        fulfillment_status: :fulfilled,
        delivery_photo_slug: "local:///uploads/door.jpg",
        email_delivery_photo: true
      )

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
    refute has_element?(view, "#order-confirmation-failed")

    perform_job(Edenflowers.Orders.Workers.SendDeliveredEmail, %{"primary_key" => %{"id" => order.id}},
      attempt: 3,
      max_attempts: 3
    )

    assert render(view) =~ "Couldn&#39;t email the confirmation."
    assert has_element?(view, "#order-confirmation-failed", "Check the delivery photo")
    assert has_element?(view, "#order-log li", "Fulfillment confirmation failed")
  end

  @tag capture_log: true
  test "an open page shows a receipt that failed in the background", %{conn: conn} do
    order = placed_order(paid: true)
    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
    refute has_element?(view, "#order-email-failed")

    primary_key = %{"id" => order.id}
    job = %Oban.Job{attempt: 3, max_attempts: 3, args: %{"primary_key" => primary_key}}

    Edenflowers.Orders.Workers.SendConfirmationEmail.handle_error(
      job,
      RuntimeError.exception("mail server down"),
      primary_key,
      []
    )

    assert render(view) =~ "Couldn&#39;t email the receipt."
    assert has_element?(view, "#order-email-failed", "Couldn't email the receipt.")
    assert has_element?(view, "#order-log li", "Receipt failed")
  end

  test "the log keeps the address a confirmation went to after the customer's email changes", %{conn: conn} do
    order = placed_order(fulfillment_status: :fulfilled)
    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
    view |> element(~s|button[phx-click="email_fulfillment_confirmation"]|) |> render_click()
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :default)

    order |> Ash.reload!(authorize?: false) |> Ash.Seed.update!(%{customer_email: "new@example.com"})
    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, "#order-log li", ~r/Fulfillment confirmation emailed.*ada@example\.com/s)
    refute has_element?(view, "#order-log li", ~r/Fulfillment confirmation emailed.*new@example\.com/s)
  end

  describe "confirming a delivery" do
    test "reopening after native drawer dismissal forgets the previous photo", %{conn: conn} do
      order = placed_order(fulfillment_method: :delivery)
      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
      view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
      view |> form("#confirm-fulfillment-form", fulfillment: %{customer_home: "false"}) |> render_change()

      view
      |> file_input("#confirm-fulfillment-form", "photo_fulfillment[photo]", [
        %{name: "old-door.jpg", content: "jpeg bytes", type: "image/jpeg"}
      ])
      |> render_upload("old-door.jpg")

      view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
      view |> form("#confirm-fulfillment-form", fulfillment: %{customer_home: "false"}) |> render_change()
      view |> form("#confirm-fulfillment-form") |> render_submit()

      assert has_element?(view, "#confirm-fulfillment-dialog [role=alert]", "Take a photo of where you left the order.")
      assert Orders.get_order_for_admin!(order.id, actor: %{admin: true}).fulfillment_status == :pending
      refute_enqueued(worker: Edenflowers.Orders.Workers.SendDeliveredEmail)
    end

    test "the customer was home: fulfils with no photo", %{conn: conn} do
      order = placed_order(fulfillment_method: :delivery)

      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

      view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
      assert has_element?(view, "#confirm-fulfillment-form label", "Email delivery confirmation")
      assert has_element?(view, "#confirm-fulfillment-form", "To: ada@example.com")
      assert has_element?(view, ~s|#confirm-fulfillment-form input[name="fulfillment[email_customer]"][checked]|)
      view |> form("#confirm-fulfillment-form", fulfillment: %{customer_home: "true"}) |> render_change()
      refute has_element?(view, "#confirm-fulfillment-form input[type=file]")
      view |> form("#confirm-fulfillment-form") |> render_submit()

      assert has_element?(view, "#order-status", "Fulfilled")
      refute has_element?(view, "#order-delivery-photo")

      assert_enqueued(
        worker: Edenflowers.Orders.Workers.SendDeliveredEmail,
        args: %{"primary_key" => %{"id" => order.id}}
      )
    end

    test "nobody was home: keeps the photo under a name that can't be guessed", %{conn: conn} do
      order = placed_order(fulfillment_method: :delivery)

      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
      view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
      view |> form("#confirm-fulfillment-form", fulfillment: %{customer_home: "false"}) |> render_change()

      view
      |> file_input("#confirm-fulfillment-form", "photo_fulfillment[photo]", [
        %{name: "IMG_0001.JPG", content: "jpeg bytes", type: "image/jpeg"}
      ])
      |> render_upload("IMG_0001.JPG")

      view |> form("#confirm-fulfillment-form", fulfillment: %{email_photo: "false"}) |> render_submit()

      assert has_element?(view, "#order-status", "Fulfilled")
      assert has_element?(view, "#order-delivery-photo img")

      reloaded = Orders.get_order_for_admin!(order.id, actor: %{admin: true})
      assert "local:///uploads/" <> file = reloaded.delivery_photo_slug
      assert file =~ ~r/\A[0-9a-f]{32}\.jpg\z/
      refute reloaded.email_delivery_photo
    end

    test "nobody was home: won't confirm without a photo", %{conn: conn} do
      order = placed_order(fulfillment_method: :delivery)

      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
      view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
      view |> form("#confirm-fulfillment-form", fulfillment: %{customer_home: "false"}) |> render_change()
      view |> form("#confirm-fulfillment-form") |> render_submit()

      assert has_element?(view, "#confirm-fulfillment-dialog [role=alert]", "Take a photo of where you left the order.")
      assert Orders.get_order_for_admin!(order.id, actor: %{admin: true}).fulfillment_status == :pending
    end
  end

  describe "choosing whether to email the customer" do
    test "the photo email choice follows the confirmation choice", %{conn: conn} do
      order = placed_order(fulfillment_method: :delivery)
      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
      view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
      view |> form("#confirm-fulfillment-form", fulfillment: %{customer_home: "false"}) |> render_change()
      assert has_element?(view, ~s|input[name="fulfillment[email_photo]"][type="checkbox"]|)

      view |> form("#confirm-fulfillment-form", fulfillment: %{email_customer: "false"}) |> render_change()
      refute has_element?(view, ~s|input[name="fulfillment[email_photo]"]|)

      view
      |> file_input("#confirm-fulfillment-form", "photo_fulfillment[photo]", [
        %{name: "door.jpg", content: "jpeg bytes", type: "image/jpeg"}
      ])
      |> render_upload("door.jpg")

      view |> form("#confirm-fulfillment-form") |> render_submit()
      order = Orders.get_order_for_admin!(order.id, actor: %{admin: true})
      assert order.fulfillment_status == :fulfilled
      refute order.email_delivery_photo
      refute_enqueued(worker: Edenflowers.Orders.Workers.SendDeliveredEmail)
    end

    test "the choice starts ticked each time the form opens", %{conn: conn} do
      order = placed_order()

      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
      view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
      assert_push_event(view, "js-exec", %{to: "#confirm-fulfillment", attr: "phx-show"})
      assert has_element?(view, "dialog.slide-drawer--right #confirm-fulfillment-form")
      assert has_element?(view, "#confirm-fulfillment-form label", "Email collection confirmation")
      assert has_element?(view, ~s|#confirm-fulfillment-form input[name="fulfillment[email_customer]"][checked]|)

      view |> form("#confirm-fulfillment-form", fulfillment: %{email_customer: "false"}) |> render_change()
      refute has_element?(view, ~s|#confirm-fulfillment-form input[name="fulfillment[email_customer]"][checked]|)

      render_click(view, "cancel_fulfillment")
      view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
      assert has_element?(view, ~s|#confirm-fulfillment-form input[name="fulfillment[email_customer]"][checked]|)
    end

    test "no: fulfils without queueing the delivered email", %{conn: conn} do
      order = placed_order()

      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
      view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
      view |> form("#confirm-fulfillment-form", fulfillment: %{email_customer: "false"}) |> render_change()
      view |> form("#confirm-fulfillment-form") |> render_submit()

      assert has_element?(view, "#order-status", "Fulfilled")

      reloaded = Orders.get_order_for_admin!(order.id, actor: %{admin: true})
      assert reloaded.fulfillment_status == :fulfilled
      refute_enqueued(worker: Edenflowers.Orders.Workers.SendDeliveredEmail)
    end
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
    # Gift is also surfaced prominently in the header, matching the Overview.
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
    order = placed_order(refunded: true)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, "header", "Refunded")
  end

  test "logs payments and refunds with their amounts", %{conn: conn} do
    order = placed_order()
    generate(payment(order_id: order.id, amount: Decimal.new("46.50")))
    generate(payment(order_id: order.id, amount: Decimal.new("-10.00"), method: :cash))

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, "#order-log", "Paid €46.50 · Stripe")
    assert has_element?(view, "#order-log", "Refunded €10.00 · Cash")
  end

  test "fetches a refund from Stripe whose webhook never arrived", %{conn: conn} do
    order = placed_order()
    generate(payment(order_id: order.id, amount: Decimal.new("46.50"), payment_intent_id: "pi_missed_refund"))

    Mox.expect(StripeAPI.Mock, :list_refunds, 2, fn "pi_missed_refund" ->
      {:ok, [%{id: "re_missed", payment_intent: "pi_missed_refund", amount: 1000, status: "succeeded"}]}
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    view |> element(~s|button[phx-click="fetch_stripe_refunds"]|) |> render_click()
    assert has_element?(view, "#order-log", "Refunded €10.00 · Stripe")

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
    to_refund = StripeAPI.to_stripe_amount(Decimal.abs(balance))
    test_pid = self()

    StripeAPI.Mock
    |> Mox.stub(:list_refunds, fn
      "pi_new" -> {:ok, [%{id: "re_pending", amount: 1000, status: "pending"}]}
      "pi_old" -> {:ok, []}
    end)
    |> Mox.expect(:create_refund, 2, fn payment_intent_id, cents, key ->
      assert key == "refund-#{order.id}-2-#{payment_intent_id}"
      send(test_pid, {:refunded, payment_intent_id, cents})
      {:ok, %{id: "re_#{payment_intent_id}", payment_intent: payment_intent_id, amount: cents, status: "succeeded"}}
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    view |> element(~s|button[phx-click="refund_with_stripe"]|) |> render_click()

    # The pending €10 on pi_new is already on its way, so it comes off what's owed.
    assert_received {:refunded, "pi_new", 2000}
    assert_received {:refunded, "pi_old", rest} when rest == to_refund - 1000 - 2000
  end

  test "two refund clicks send the same idempotency key" do
    order = placed_order()
    generate(payment(order_id: order.id, amount: Decimal.new("200.00"), payment_intent_id: "pi_paid"))
    test_pid = self()

    # Stripe hasn't listed the first refund yet when the second click arrives.
    StripeAPI.Mock
    |> Mox.stub(:list_refunds, fn "pi_paid" -> {:ok, []} end)
    |> Mox.expect(:create_refund, 2, fn "pi_paid", cents, key ->
      send(test_pid, {:refund_key, key})
      {:ok, %{id: "re_pending", payment_intent: "pi_paid", amount: cents, status: "pending"}}
    end)

    assert {:ok, [_pending]} = Edenflowers.Payments.refund_balance(order)
    assert {:ok, [_pending]} = Edenflowers.Payments.refund_balance(order)

    assert_received {:refund_key, first_key}
    assert_received {:refund_key, second_key}
    assert first_key == "refund-#{order.id}-1-pi_paid"
    assert second_key == first_key
  end

  test "a create_refund error on the second payment keeps the first refund recorded and reports the error", %{
    conn: conn
  } do
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

    StripeAPI.Mock
    |> Mox.stub(:list_refunds, fn _payment_intent_id -> {:ok, []} end)
    |> Mox.expect(:create_refund, fn "pi_new", cents, _key ->
      {:ok, %{id: "re_pi_new", payment_intent: "pi_new", amount: cents, status: "succeeded"}}
    end)
    |> Mox.expect(:create_refund, fn "pi_old", _cents, _key -> {:error, :card_declined} end)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    {html, log} =
      ExUnit.CaptureLog.with_log(fn ->
        view |> element(~s|button[phx-click="refund_with_stripe"]|) |> render_click()
      end)

    assert html =~ "Could not refund with Stripe."
    assert log =~ ":card_declined"

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
    assert has_element?(view, "#order-log", "Refunded €30.00 · Stripe")
  end

  test "doesn't refund again what Stripe already has refunds for", %{conn: conn} do
    order = placed_order()
    generate(payment(order_id: order.id, amount: Decimal.new("500.00"), payment_intent_id: "pi_paid"))

    balance = Orders.get_order_for_admin!(order.id, authorize?: false).balance
    pending = StripeAPI.to_stripe_amount(Decimal.abs(balance)) - 1000

    StripeAPI.Mock
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

    assert has_element?(view, "#order-log", "Refunded €10.00 · Stripe")
  end

  test "omits the card widget for a whitespace-only card message", %{conn: conn} do
    order = placed_order()

    # Ash trims strings to nil on the way in, so only rows written outside Ash can hold this
    Edenflowers.Repo.query!("UPDATE orders SET card_message = '   ' WHERE id = $1", [Ecto.UUID.dump!(order.id)])

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    refute has_element?(view, "#order-card")
  end

  test "shows the phone under customer and omits recipient for a non-gift order", %{conn: conn} do
    order = placed_order(recipient_phone_number: "040 123 4567")

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, "#order-customer", "Customer")
    assert has_element?(view, ~s|#order-customer a[href="tel:040 123 4567"]|)
    refute has_element?(view, "#order-recipient")
  end

  test "offers ready-for-pickup message links in the customer's language", %{conn: conn} do
    order = placed_order(order_reference: "DETAIL", recipient_phone_number: "040 123 4567", locale: "sv-FI")

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

    assert has_element?(view, "#order-queue-nav", "2 of 3 to fulfil")
    assert has_element?(view, ~s|#order-queue-nav a[href="/admin/orders/#{earlier.id}"]|)
    assert has_element?(view, ~s|#order-queue-nav a[href="/admin/orders/#{later.id}"]|)
  end

  test "keeps stepping after marking an order fulfilled and counts what is left", %{conn: conn} do
    current = placed_order(order_reference: "CURRENT", fulfillment_date: ~D[2026-06-11])
    later = placed_order(order_reference: "LATER", fulfillment_date: ~D[2026-06-12])
    placed_order(order_reference: "LATEST", fulfillment_date: ~D[2026-06-13])

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{current.id}")

    view
    |> element(~s|button[phx-click="confirm_fulfillment"]|)
    |> render_click()

    view |> form("#confirm-fulfillment-form") |> render_submit()

    assert has_element?(view, "#order-queue-nav", "Fulfilled · 2 left")
    refute has_element?(view, "#order-queue-nav", "1 of 3 to fulfil")
    assert has_element?(view, ~s|#order-queue-nav a[href="/admin/orders/#{later.id}"]|)
  end

  test "omits queue stepping for an order already fulfilled", %{conn: conn} do
    order = placed_order(fulfillment_status: :fulfilled)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    refute has_element?(view, "#order-queue-nav")
  end

  test "redirects missing orders back to the admin orders table", %{conn: conn} do
    missing_id = Ash.UUID.generate()

    assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/admin/orders/#{missing_id}")
    assert to == ~p"/admin/orders"
  end
end
