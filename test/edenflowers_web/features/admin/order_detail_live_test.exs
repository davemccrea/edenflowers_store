defmodule EdenflowersWeb.Admin.OrderDetailLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  use Oban.Testing, repo: Edenflowers.Repo

  import Generator
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders

  setup :log_in_admin

  test "warns when a delivery has no phone to call", %{conn: conn} do
    missing = placed_order(fulfillment_method: :delivery, gift: true, recipient_name: "Grandma")
    phoned = placed_order(fulfillment_method: :delivery, customer_phone_number: "+358401234567")

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{missing.id}")
    assert has_element?(view, "#order-recipient #order-missing-phone", "Missing recipient phone")

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{phoned.id}")
    refute has_element?(view, "#order-missing-phone")
  end

  test "custom and online orders offer cancellation, never deletion", %{conn: conn} do
    custom = placed_order(origin: :custom, payment_intent_id: nil)
    online = placed_order()

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{online.id}")
    refute has_element?(view, ~s|button[phx-click="delete_order"]|)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{custom.id}")
    refute has_element?(view, ~s|button[phx-click="delete_order"]|)
    assert has_element?(view, ~s|button[phx-click="open_cancel"]|, "Cancel order")
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

    assert has_element?(view, ~s|button[phx-value-kind="order_details"]|)
    refute has_element?(view, "li", "Email receipt")

    order = Ash.load!(order, :grand_total, authorize?: false)
    generate(payment(order_id: order.id, amount: order.grand_total, payment_intent_id: "pi_test_menu_paid"))

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, ~s|button[phx-value-kind="receipt"]|, "Email receipt")
    refute has_element?(view, "li", "Email order details")

    Ash.Seed.update!(order, %{receipt_emailed_at: DateTime.utc_now()})

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, ~s|button[phx-value-kind="receipt"]|, "Resend receipt")
    view |> element(~s|button[phx-value-kind="receipt"]|) |> render_click()
    assert has_element?(view, "#email-drawer", "Last sent ")
  end

  test "the email drawer previews what the customer will get, without sending it", %{conn: conn} do
    order = placed_order(paid: true, locale: "en-GB")
    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    view |> element(~s|button[phx-value-kind="receipt"]|) |> render_click()
    assert has_element?(view, "#email-drawer-email-preview", "Payment received for your order for")
    assert has_element?(view, "#email-drawer-email-preview", "Attached: eden-flowers-#{order.order_reference}.pdf")

    view |> form("#email-form", email: %{message: "Thank you for coming in."}) |> render_change()
    assert has_element?(view, "#email-drawer-email-preview", "Thank you for coming in.")

    view |> form("#email-form", email: %{message: "Tack!", in_swedish: "true"}) |> render_change()
    assert has_element?(view, "#email-drawer-email-preview", "Betalning mottagen")

    assert_no_email_sent()
    refute_enqueued(worker: Edenflowers.Orders.Workers.SendReceiptEmail)
  end

  test "a payment reminder isn't offered for an order paid by invoice", %{conn: conn} do
    order = placed_order()

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
    assert has_element?(view, ~s|button[phx-value-kind="payment_reminder"]|, "Send payment reminder")

    Ash.Seed.update!(order, %{payment_terms: :invoice})

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
    refute has_element?(view, ~s|button[phx-value-kind="payment_reminder"]|)
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

    assert has_element?(view, "#order-payment-summary", "84,00 €")
    assert has_element?(view, "#order-payment-summary", "−16,80 €")
    assert has_element?(view, "#order-payment-summary", "71,70 €")
  end

  test "marking an order fulfilled flips the status and shows the fulfilled badge", %{conn: conn} do
    order = placed_order()

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    refute has_element?(view, ~s|button[phx-value-kind="fulfillment"]|)
    view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
    refute has_element?(view, ~s|#confirm-fulfillment-form input[type="checkbox"]|)
    view |> form("#confirm-fulfillment-form") |> render_submit()

    refute has_element?(view, ~s|button[phx-click="confirm_fulfillment"]|)
    assert has_element?(view, "#order-status", "Fulfilled")
    assert render(view) =~ "Order marked as collected."
    refute render(view) =~ "Confirmation queued."
    refute_enqueued(worker: Edenflowers.Orders.Workers.SendFulfillmentEmail)

    reloaded = Orders.get_order_for_admin!(order.id, actor: %{admin: true})
    assert reloaded.fulfillment_status == :fulfilled
  end

  test "fulfills a pickup with no customer email", %{conn: conn} do
    order = placed_order(customer_email: nil, customer_phone_number: "044 222 3344")

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
    view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
    refute has_element?(view, ~s|#confirm-fulfillment-form input[type="checkbox"]|)
    refute has_element?(view, "#confirm-fulfillment-form", "no confirmation will be emailed")
    view |> form("#confirm-fulfillment-form") |> render_submit()

    assert has_element?(view, "#order-status", "Fulfilled")
    assert Orders.get_order_for_admin!(order.id, actor: %{admin: true}).fulfillment_status == :fulfilled
    refute_enqueued(worker: Edenflowers.Orders.Workers.SendFulfillmentEmail)
  end

  test "emails the confirmation from the menu and logs it when sent", %{conn: conn} do
    order = placed_order(fulfillment_method: :delivery, fulfillment_status: :fulfilled)
    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    view |> element(~s|button[phx-value-kind="fulfillment"]|, "Email confirmation") |> render_click()

    assert view |> form("#email-form", email: %{message: "Thank you for choosing us."}) |> render_submit() =~
             "Confirmation queued."

    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :default)
    assert_email_sent(fn email -> assert email.text_body =~ "Thank you for choosing us." end)

    assert has_element?(view, "#order-log li", ~r/Fulfillment confirmation emailed.*Thank you for choosing us\./s)
    assert has_element?(view, "#order-log li", ~r/Fulfillment confirmation emailed.*ada@example\.com/s)
    assert has_element?(view, ~s|button[phx-value-kind="fulfillment"]|, "Resend confirmation")

    order |> Ash.reload!(authorize?: false) |> Ash.Seed.update!(%{customer_email: "new@example.com"})
    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, "#order-log li", ~r/Fulfillment confirmation emailed.*ada@example\.com/s)
    refute has_element?(view, "#order-log li", ~r/Fulfillment confirmation emailed.*new@example\.com/s)
  end

  @tag capture_log: true
  test "an open page shows a confirmation that failed in the background", %{conn: conn} do
    Req.Test.stub(Edenflowers.Orders.Order.Changes.SendFulfillmentEmail, fn conn ->
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

    perform_job(Edenflowers.Orders.Workers.SendFulfillmentEmail, %{"primary_key" => %{"id" => order.id}},
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

    Edenflowers.Orders.Workers.SendReceiptEmail.handle_error(
      job,
      RuntimeError.exception("mail server down"),
      primary_key,
      []
    )

    assert render(view) =~ "Couldn&#39;t email the receipt."
    assert has_element?(view, "#order-email-failed", "Couldn't email the receipt.")
    assert has_element?(view, "#order-log li", "Receipt failed")
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
      refute_enqueued(worker: Edenflowers.Orders.Workers.SendFulfillmentEmail)
    end

    test "the customer was home: fulfils with no photo and, by default, no email", %{conn: conn} do
      order = placed_order(fulfillment_method: :delivery)

      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

      view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
      assert has_element?(view, "#confirm-fulfillment-form label", "Email delivery confirmation")
      assert has_element?(view, "#confirm-fulfillment-form", "To: ada@example.com")
      view |> form("#confirm-fulfillment-form", fulfillment: %{customer_home: "true"}) |> render_change()
      refute has_element?(view, ~s|#confirm-fulfillment-form input[name="fulfillment[email_customer]"][checked]|)
      refute has_element?(view, "#confirm-fulfillment-form input[type=file]")
      view |> form("#confirm-fulfillment-form") |> render_submit()

      assert has_element?(view, "#order-status", "Fulfilled")
      refute has_element?(view, "#order-delivery-photo")
      refute_enqueued(worker: Edenflowers.Orders.Workers.SendFulfillmentEmail)
    end

    test "nobody was home: requires a photo, then names it after the time and order reference", %{conn: conn} do
      order = placed_order(fulfillment_method: :delivery)

      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
      view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
      view |> form("#confirm-fulfillment-form", fulfillment: %{customer_home: "false"}) |> render_change()

      view |> form("#confirm-fulfillment-form") |> render_submit()
      assert has_element?(view, "#confirm-fulfillment-dialog [role=alert]", "Take a photo of where you left the order.")
      assert Orders.get_order_for_admin!(order.id, actor: %{admin: true}).fulfillment_status == :pending

      view
      |> file_input("#confirm-fulfillment-form", "photo_fulfillment[photo]", [
        %{name: "IMG_0001.JPG", content: "jpeg bytes", type: "image/jpeg"}
      ])
      |> render_upload("IMG_0001.JPG")

      view |> form("#confirm-fulfillment-form", fulfillment: %{email_customer: "false"}) |> render_submit()

      assert has_element?(view, "#order-status", "Fulfilled")
      assert has_element?(view, "#order-delivery-photo a", "View photo")

      reloaded = Orders.get_order_for_admin!(order.id, actor: %{admin: true})
      assert "local:///uploads/" <> file = reloaded.delivery_photo_slug
      assert file =~ ~r/\A\d{8}-\d{6}_#{reloaded.order_reference}\.jpg\z/
      refute reloaded.email_delivery_photo
    end
  end

  describe "choosing whether to email the customer" do
    test "nobody home sends Left at the door with the photo, unless Jennie unticks it", %{conn: conn} do
      order = placed_order(fulfillment_method: :delivery, locale: "en-GB")
      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
      view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
      view |> form("#confirm-fulfillment-form", fulfillment: %{customer_home: "false"}) |> render_change()
      assert has_element?(view, "#fulfillment-email-preview", "was left at the door")
      assert has_element?(view, "#fulfillment-email-preview", "Attached: eden-flowers-delivery.jpg")

      view |> form("#confirm-fulfillment-form", fulfillment: %{email_customer: "false"}) |> render_change()
      refute has_element?(view, "#fulfillment-email-preview")

      view
      |> file_input("#confirm-fulfillment-form", "photo_fulfillment[photo]", [
        %{name: "door.jpg", content: "jpeg bytes", type: "image/jpeg"}
      ])
      |> render_upload("door.jpg")

      view |> form("#confirm-fulfillment-form") |> render_submit()
      order = Orders.get_order_for_admin!(order.id, actor: %{admin: true})
      assert order.fulfillment_status == :fulfilled
      refute order.email_delivery_photo
      refute_enqueued(worker: Edenflowers.Orders.Workers.SendFulfillmentEmail)
    end

    test "a delivery starts unticked each time the form opens", %{conn: conn} do
      order = placed_order(fulfillment_method: :delivery)

      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
      view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
      assert_push_event(view, "js-exec", %{to: "#confirm-fulfillment", attr: "phx-show"})
      assert has_element?(view, "#confirm-fulfillment-form label", "Email delivery confirmation")
      refute has_element?(view, ~s|#confirm-fulfillment-form input[name="fulfillment[email_customer]"][checked]|)

      view |> form("#confirm-fulfillment-form", fulfillment: %{email_customer: "true"}) |> render_change()
      assert has_element?(view, ~s|#confirm-fulfillment-form input[name="fulfillment[email_customer]"][checked]|)

      view |> element("#confirm-fulfillment-form button", "Cancel") |> render_click()
      view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
      refute has_element?(view, ~s|#confirm-fulfillment-form input[name="fulfillment[email_customer]"][checked]|)
    end

    test "a gift, or a delivery left while nobody was home, starts ticked", %{conn: conn} do
      checked = ~s|#confirm-fulfillment-form input[name="fulfillment[email_customer]"][checked]|

      gift = placed_order(fulfillment_method: :delivery, gift: true, recipient_name: "Grace Hopper")
      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{gift.id}")
      view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
      assert has_element?(view, checked)
      view |> form("#confirm-fulfillment-form", fulfillment: %{customer_home: "true"}) |> render_change()
      assert has_element?(view, checked)

      order = placed_order(fulfillment_method: :delivery)
      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
      view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
      view |> form("#confirm-fulfillment-form", fulfillment: %{customer_home: "false"}) |> render_change()
      assert has_element?(view, checked)
    end

    test "no: fulfils without queueing the fulfillment email", %{conn: conn} do
      # A gift starts ticked, so unticking is a real choice.
      order = placed_order(fulfillment_method: :delivery, gift: true, recipient_name: "Grace Hopper")

      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
      view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()

      view |> form("#confirm-fulfillment-form", fulfillment: %{customer_home: "true"}) |> render_change()

      view
      |> form("#confirm-fulfillment-form", fulfillment: %{customer_home: "true", email_customer: "false"})
      |> render_change()

      view |> form("#confirm-fulfillment-form") |> render_submit()

      assert has_element?(view, "#order-status", "Fulfilled")

      reloaded = Orders.get_order_for_admin!(order.id, actor: %{admin: true})
      assert reloaded.fulfillment_status == :fulfilled
      refute_enqueued(worker: Edenflowers.Orders.Workers.SendFulfillmentEmail)
    end
  end

  test "shows customer and recipient as separate sections for a gift order", %{conn: conn} do
    order =
      placed_order(
        gift: true,
        recipient_name: "Grace Hopper",
        customer_phone_number: "040 123 4567"
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

  test "fetches a refund from Stripe whose webhook never arrived", %{conn: conn} do
    order = placed_order()
    generate(payment(order_id: order.id, amount: Decimal.new("46.50"), payment_intent_id: "pi_missed_refund"))

    Mox.expect(StripeAPI.Mock, :list_refunds, 2, fn "pi_missed_refund" ->
      {:ok, [%{id: "re_missed", payment_intent: "pi_missed_refund", amount: 1000, status: "succeeded"}]}
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, "#order-log", "Paid 46,50 € · Stripe")
    view |> element(~s|button[phx-click="fetch_stripe_refunds"]|) |> render_click()
    assert has_element?(view, "#order-log", "Refunded 10,00 € · Stripe")

    assert view |> element(~s|button[phx-click="fetch_stripe_refunds"]|) |> render_click() =~
             "No new refunds in Stripe."
  end

  defp refund_from_page(view, params) do
    view |> element("#order-actions button", "Refund") |> render_click()
    view |> form("#order-refund-form", refund: params) |> render_submit()
  end

  test "two refund clicks send the same idempotency key" do
    order = placed_order()
    generate(payment(order_id: order.id, amount: Decimal.new("200.00"), payment_intent_id: "pi_paid"))
    test_pid = self()

    # Stripe hasn't listed the first refund yet when the second click arrives.
    StripeAPI.Mock
    |> Mox.stub(:list_refunds, fn "pi_paid" -> {:ok, []} end)
    |> Mox.expect(:create_refund, 2, fn "pi_paid", cents, key, _metadata ->
      send(test_pid, {:refund_key, key})
      {:ok, %{id: "re_pending", payment_intent: "pi_paid", amount: cents, status: "pending"}}
    end)

    assert {:ok, [_pending]} = Edenflowers.Payments.refund_amount(order, Decimal.new("50.00"), nil)
    assert {:ok, [_pending]} = Edenflowers.Payments.refund_amount(order, Decimal.new("50.00"), nil)

    assert_received {:refund_key, first_key}
    assert_received {:refund_key, second_key}
    assert first_key == "refund-#{order.id}-1-5000-pi_paid"
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
    |> Mox.expect(:create_refund, fn "pi_new", cents, key, _metadata ->
      assert key == "refund-#{order.id}-2-10000-pi_new"
      {:ok, %{id: "re_pi_new", payment_intent: "pi_new", amount: cents, status: "succeeded"}}
    end)
    |> Mox.expect(:create_refund, fn "pi_old", _cents, key, _metadata ->
      assert key == "refund-#{order.id}-2-10000-pi_old"
      {:error, :card_declined}
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    {html, log} = ExUnit.CaptureLog.with_log(fn -> refund_from_page(view, %{amount: "100", how: "stripe"}) end)

    assert html =~ "Could not refund with Stripe."
    assert log =~ ":card_declined"

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
    assert has_element?(view, "#order-log", "Refunded 30,00 € · Stripe")
  end

  test "records a refund Stripe made that we missed before refunding more", %{conn: conn} do
    order = placed_order()
    generate(payment(order_id: order.id, amount: Decimal.new("500.00"), payment_intent_id: "pi_paid"))

    StripeAPI.Mock
    |> Mox.stub(:list_refunds, fn "pi_paid" ->
      {:ok, [%{id: "re_missed", payment_intent: "pi_paid", amount: 1000, status: "succeeded"}]}
    end)
    |> Mox.expect(:create_refund, fn "pi_paid", 2000, _key, _metadata ->
      {:ok, %{id: "re_new", payment_intent: "pi_paid", amount: 2000, status: "succeeded"}}
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
    refund_from_page(view, %{amount: "20", how: "stripe"})

    assert has_element?(view, "#order-log", "Refunded 10,00 € · Stripe")
    assert has_element?(view, "#order-log", "Refunded 20,00 € · Stripe")
  end

  test "offers ready-for-pickup message links in the customer's language", %{conn: conn} do
    order = placed_order(order_reference: "DETAIL", customer_phone_number: "040 123 4567", locale: "sv-FI")

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    body = "Hej%20Ada%2C%20din%20best%C3%A4llning%20DETAIL"
    assert has_element?(view, ~s|#order-customer a[href^="sms:+358401234567?&body=#{body}"]|)
    assert has_element?(view, ~s|#order-customer a[href^="https://wa.me/358401234567?text=#{body}"]|)
  end

  test "omits ready-for-pickup links for deliveries and fulfilled pickups", %{conn: conn} do
    delivery =
      placed_order(
        customer_phone_number: "040 123 4567",
        fulfillment_method: :delivery,
        delivery_address: "Kauppapuistikko 20, 65100 Vaasa"
      )

    fulfilled =
      placed_order(
        order_reference: "FULFILLED",
        customer_phone_number: "040 123 4567",
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

  describe "refund" do
    test "Refund is offered only once nothing is to collect", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{placed_order(paid: "40.00").id}")
      refute has_element?(view, "#order-actions button", "Refund")

      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{placed_order(paid: true).id}")
      assert has_element?(view, "#order-actions button", "Refund")
      refute has_element?(view, "#order-refund-form")

      view |> element("#order-actions button", "Refund") |> render_click()

      assert has_element?(view, "#settlement-drawer #order-refund-form")
    end

    test "a part refund by cash is recorded with its reason and emails the customer", %{conn: conn} do
      order = placed_order()
      generate(payment(order_id: order.id, method: :cash, amount: Decimal.new("88.50")))

      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
      refund_from_page(view, %{amount: "20,00", how: "cash", note: "Wilted early"})

      assert has_element?(view, "#order-log", "Refunded 20,00 € · Cash")
      assert has_element?(view, "#order-log", "Wilted early")
      assert has_element?(view, "#order-payments", "Refund · Cash")
      refute render(view) =~ "To collect"
      assert [_job] = all_enqueued(worker: Edenflowers.Payments.Workers.SendRefundedEmail)
    end

    test "a part refund by Stripe is sent and recorded, leaving nothing to collect", %{conn: conn} do
      order = placed_order()
      generate(payment(order_id: order.id, amount: Decimal.new("88.50"), payment_intent_id: "pi_paid"))

      StripeAPI.Mock
      |> Mox.stub(:list_refunds, fn "pi_paid" -> {:ok, []} end)
      |> Mox.expect(:create_refund, fn "pi_paid", 2_000, _key, %{"reason" => "refund"} ->
        {:ok, %{id: "re_refund", payment_intent: "pi_paid", amount: 2_000, status: "succeeded"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
      view |> element("#order-actions button", "Refund") |> render_click()
      assert has_element?(view, ~s|#order-refund-how option[value="stripe"][selected]|)

      assert view
             |> form("#order-refund-form", refund: %{amount: "20.00", how: "stripe", email_customer: "false"})
             |> render_submit() =~ "Refunded with Stripe."

      assert has_element?(view, "#order-log", "Refunded 20,00 € · Stripe")
      refute render(view) =~ "To collect"
      refute_enqueued(worker: Edenflowers.Payments.Workers.SendRefundedEmail)
    end

    test "the form offers the order's refund methods and starts at its default", %{conn: conn} do
      order = placed_order()
      generate(payment(order_id: order.id, method: :mobilepay, amount: Decimal.new("88.50")))
      order = Ash.load!(order, [:refund_methods, :default_refund_method], authorize?: false)

      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
      view |> element("#order-actions button", "Refund") |> render_click()

      offered =
        view
        |> render()
        |> LazyHTML.from_document()
        |> LazyHTML.query("#order-refund-how option")
        |> LazyHTML.attribute("value")

      assert offered == Enum.map(order.refund_methods, &to_string/1)
      assert order.default_refund_method == :mobilepay
      assert has_element?(view, ~s|#order-refund-how option[value="mobilepay"][selected]|)
    end
  end
end
