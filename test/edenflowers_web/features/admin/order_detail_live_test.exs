defmodule EdenflowersWeb.Admin.OrderDetailLiveTest do
  # Run synchronously so broadcasts from other tests on the shared order topic
  # cannot trigger warnings that these tests expect to be absent.
  use EdenflowersWeb.ConnCase, async: false

  use Oban.Testing, repo: Edenflowers.Repo

  import Generator
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders

  setup :log_in_admin

  test "an external full payment only warns until reload makes refunds available", %{conn: conn, admin: admin} do
    order = placed_order(payment_intent_id: nil)
    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    Orders.record_payment!(order, order.grand_total, :cash, actor: admin)

    assert has_element?(view, "#editor-stale-notice")
    refute has_element?(view, "#order-actions button", "Refund")
    assert has_element?(view, "#order-balance-settle")
    view |> element("#editor-stale-notice button") |> render_click()
    {path, _} = assert_redirect(view)
    {:ok, view, _} = live(conn, path)
    assert has_element?(view, "#order-actions button", "Refund")
    view |> element("#order-actions button", "Refund") |> render_click()
    assert has_element?(view, ~s|#order-refund-how option[value="cash"][selected]|)

    view
    |> form("#order-refund-form", refund: %{amount: "10.00", payment_method: "cash", email_customer?: "false"})
    |> render_submit()

    fresh = Orders.get_order_for_admin!(order.id, actor: admin)
    assert Decimal.eq?(fresh.amount_held, Decimal.sub(order.grand_total, 10))
  end

  test "undoing a payment elsewhere leaves payment controls unchanged until reload", %{conn: conn, admin: admin} do
    order = placed_order(payment_intent_id: nil)
    payment = generate(payment(order_id: order.id, method: :cash, amount: order.grand_total))
    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    Orders.undo_payment!(order, payment.id, actor: admin)

    assert has_element?(view, "#editor-stale-notice")
    refute has_element?(view, "#order-balance-settle")
    view |> element("#editor-stale-notice button") |> render_click()
    {path, _} = assert_redirect(view)
    {:ok, view, _} = live(conn, path)
    assert has_element?(view, "#order-balance-settle")
    view |> element("#order-balance-settle") |> render_click()

    view
    |> form("#order-balance-form", payment: %{payment_method: "cash", email_receipt?: "false"})
    |> render_submit()

    fresh = Orders.get_order_for_admin!(order.id, actor: admin)
    assert Decimal.eq?(fresh.amount_paid, order.grand_total)
    refute fresh.to_collect?
  end

  test "external changes leave saved data, settlement input and unsaved notes alone", %{conn: conn, admin: admin} do
    order = placed_order()
    {:ok, view, _} = live(conn, ~p"/admin/orders/#{order.id}")
    view |> form("#florist-note-form", note: %{florist_note: "Keep this draft"}) |> render_change()
    view |> element("button[phx-click=open_settlement]") |> render_click()

    view
    |> form("#order-balance-form", payment: %{amount: "12", payment_method: "cash"})
    |> render_change(%{"_target" => ["payment", "amount"]})

    Orders.update_florist_note!(order, %{florist_note: "Saved elsewhere"}, actor: admin)
    assert has_element?(view, "#florist-note-form textarea", "Keep this draft")
    assert has_element?(view, "#order-balance-form input[name='payment[amount]'][value='12']")
    refute has_element?(view, "#order-log", "Saved elsewhere")
    assert has_element?(view, "#editor-stale-notice")
    assert has_element?(view, "#settlement-drawer-stale-notice[role=alert]")

    view |> element("#editor-stale-notice button") |> render_click()
    {path, _} = assert_redirect(view)
    {:ok, view, _} = live(conn, path)
    assert has_element?(view, "#florist-note-form textarea", "Saved elsewhere")
    refute has_element?(view, "#editor-stale-notice")
  end

  test "a saved note still warns about the next external save and may be overwritten", %{conn: conn, admin: admin} do
    order = placed_order()
    {:ok, view, _} = live(conn, ~p"/admin/orders/#{order.id}")
    view |> form("#florist-note-form", note: %{florist_note: "My note"}) |> render_change()
    view |> form("#florist-note-form") |> render_submit()
    refute has_element?(view, "#editor-stale-notice")

    Orders.update_florist_note!(order, %{florist_note: "Next note"}, actor: admin)
    assert has_element?(view, "#editor-stale-notice[role=alert]")
    view |> form("#florist-note-form", note: %{florist_note: "Save anyway"}) |> render_submit()
    assert Orders.get_order_for_admin!(order.id, actor: admin).florist_note == "Save anyway"
    refute has_element?(view, "#editor-stale-notice")
  end

  test "a successful readiness action reloads the order", %{conn: conn} do
    order = placed_order()
    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
    view |> element("button", "Mark as ready") |> render_click()

    assert_push_event(view, "order-ready", %{})
    assert has_element?(view, "#order-status", "Ready for pickup")
    assert has_element?(view, "#order-log", "Marked ready")
  end

  test "handover is available only while the order is ready", %{conn: conn, admin: admin} do
    for {method, label, ready_status} <- [
          {:pickup, "Mark as collected", "Ready for pickup"},
          {:delivery, "Mark as delivered", "Ready"}
        ] do
      order = placed_order(fulfillment_method: method, customer_phone_number: "040 123 4567")
      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
      refute has_element?(view, "#order-ready-messages")
      refute has_element?(view, ~s|button[phx-click="confirm_fulfillment"]|)
      refute has_element?(view, "#confirm-fulfillment-form")

      view |> element("button", "Mark as ready") |> render_click()
      assert_push_event(view, "order-ready", %{})
      assert Orders.get_order_for_admin!(order.id, actor: admin).fulfillment_status == :ready
      assert has_element?(view, "#order-status", ready_status)
      assert has_element?(view, "#order-ready-at", "Marked ready")
      assert has_element?(view, "#order-log", "Marked ready")
      assert has_element?(view, ~s|button[phx-click="confirm_fulfillment"]|, label)
      refute has_element?(view, ~s|a[href="/admin/orders/#{order.id}/edit"]|)

      if method == :pickup do
        assert has_element?(view, "#order-ready-messages", "Text ready for pickup")
      end

      view |> element("button", "Undo ready") |> render_click()
      refute_push_event(view, "order-ready", %{})
      assert Orders.get_order_for_admin!(order.id, actor: admin).fulfillment_status == :pending
      assert has_element?(view, "button", "Mark as ready")
      refute has_element?(view, "#order-ready-messages")
      refute has_element?(view, ~s|button[phx-click="confirm_fulfillment"]|)
      refute has_element?(view, "#confirm-fulfillment-form")
      assert has_element?(view, ~s|a[href="/admin/orders/#{order.id}/edit"]|)
    end
  end

  test "does not celebrate a readiness change that fails", %{conn: conn, admin: admin} do
    order = placed_order()
    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
    Orders.mark_order_ready!(order, actor: admin)

    render_click(view, "mark_ready")

    refute_push_event(view, "order-ready", %{})
    assert has_element?(view, "#flash-error", "The order has changed")
  end

  test "warns when a delivery has no phone to call", %{conn: conn} do
    missing = placed_order(fulfillment_method: :delivery, gift: true, recipient_name: "Grandma")
    phoned = placed_order(fulfillment_method: :delivery, customer_phone_number: "+358401234567")

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{missing.id}")
    assert has_element?(view, "#order-recipient #order-missing-phone", "Missing recipient phone")

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{phoned.id}")
    refute has_element?(view, "#order-missing-phone")
  end

  test "links an order to the subscription it belongs to, including the one that started it", %{conn: conn} do
    subscription = generate(subscription())
    first = Ash.Seed.update!(placed_order(), %{subscription_id: subscription.id})
    occurrence = Ash.Seed.update!(placed_order(), %{subscription_id: subscription.id, origin: :subscription})
    link = ~s|a[href="/admin/subscriptions/#{subscription.id}"]|

    for order <- [first, occurrence] do
      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
      assert has_element?(view, link, "Subscription")
    end

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{placed_order().id}")
    refute has_element?(view, ~s|a[href^="/admin/subscriptions/"]|)
  end

  test "Jennie links a pass-it-on card to a gift order by typing its code, and can remove it", %{conn: conn} do
    [code] = Edenflowers.Pricing.create_pass_it_on_batch!("Skicka vidare", 1, actor: Edenflowers.Actors.system_actor())
    gift = placed_order(gift: true, recipient_name: "Anna")
    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{placed_order().id}")
    refute has_element?(view, "#link-card-form")

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{gift.id}")
    assert has_element?(view, "#order-card-missing", "No card linked to this gift")
    view |> form("#link-card-form", %{code: "NOPE00"}) |> render_submit()
    assert render(view) =~ "No pass-it-on card has the code NOPE00."

    view |> form("#link-card-form", %{code: " #{String.downcase(code)} "}) |> render_submit()
    assert has_element?(view, "#order-card-outgoing", code)
    assert has_element?(view, "#order-card-outgoing", "Not opened yet")
    refute has_element?(view, "#order-card-missing")
    assert {:ok, %{gift_order_id: gift_id}} = Edenflowers.Pricing.get_promotion_by_code(code)
    assert gift_id == gift.id
    assert has_element?(view, "#order-log", "Pass it on card #{code} linked")

    refute has_element?(view, "#order-pass-it-on button", "Remove")
    remove = element(view, "#order-actions button[data-confirm]", "Remove Pass it on card")
    render_click(remove)
    assert has_element?(view, "#order-card-missing")
    assert has_element?(view, "#order-log", "Pass it on card #{code} removed")
  end

  test "history details keep their record identity after a local save", %{conn: conn, admin: admin} do
    order = placed_order()
    Orders.update_florist_note!(order, %{florist_note: "Original arrangement"}, actor: admin)
    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    [original_id] =
      view
      |> element("#order-log details", "Original arrangement")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("details")
      |> LazyHTML.attribute("id")

    view |> form("#florist-note-form", note: %{florist_note: "Add white roses"}) |> render_submit()

    assert has_element?(view, "##{original_id}", "Original arrangement")

    [new_id] =
      view
      |> element("#order-log details", "Add white roses")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("details")
      |> LazyHTML.attribute("id")

    assert new_id != original_id
  end

  test "a delivered gift's card can no longer be linked", %{conn: conn, admin: admin} do
    [code] = Edenflowers.Pricing.create_pass_it_on_batch!("Skicka vidare", 1, actor: Edenflowers.Actors.system_actor())
    delivered = placed_order(gift: true, recipient_name: "Anna", fulfillment_status: :fulfilled)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{delivered.id}")
    assert has_element?(view, "#order-card-none", "No card went with this gift.")
    refute has_element?(view, "#link-card-form")

    assert {:error, _too_late} = Orders.link_pass_it_on_card(delivered, code, actor: admin)
  end

  test "fulfilling a gift locks its linked card, including stale removal requests", %{conn: conn, admin: admin} do
    [code] = Edenflowers.Pricing.create_pass_it_on_batch!("Skicka vidare", 1, actor: Edenflowers.Actors.system_actor())
    gift = placed_order(gift: true, recipient_name: "Anna")
    Orders.link_pass_it_on_card!(gift, code, actor: admin)
    ready = Orders.mark_order_ready!(gift, actor: admin)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{gift.id}")
    assert has_element?(view, ~s|button[phx-click="unlink_card"]|)

    view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
    view |> form("#confirm-fulfillment-form") |> render_submit()

    refute has_element?(view, ~s|button[phx-click="unlink_card"]|)
    assert has_element?(view, "#order-card-outgoing", code)
    assert {:error, _too_late} = Orders.remove_pass_it_on_card(ready, actor: admin)
    render_click(view, "unlink_card")
    assert Orders.get_order_for_admin!(gift.id, actor: admin).pass_it_on_card.gift_order_id == gift.id
    refute has_element?(view, "#order-log", "Pass it on card #{code} removed")
  end

  test "pass-it-on links show only the source gift and direct redemptions", %{conn: conn, admin: admin} do
    [first_code, second_code] =
      Edenflowers.Pricing.create_pass_it_on_batch!("Skicka vidare", 2, actor: Edenflowers.Actors.system_actor())

    {:ok, first_card} = Edenflowers.Pricing.get_promotion_by_code(first_code)
    {:ok, second_card} = Edenflowers.Pricing.get_promotion_by_code(second_code)
    gift = placed_order(gift: true, recipient_name: "Anna")
    Edenflowers.Pricing.link_card_to_gift_order!(first_card, gift.id, actor: admin)
    cancelled = placed_order(promotion_id: first_card.id, fulfillment_status: :cancelled)
    cart = generate(order(promotion_id: first_card.id))
    passed_on = placed_order(promotion_id: first_card.id, gift: true, recipient_name: "Berit")
    Edenflowers.Pricing.link_card_to_gift_order!(second_card, passed_on.id, actor: admin)
    brought_in = placed_order(promotion_id: second_card.id)
    sibling = placed_order(promotion_id: first_card.id)

    neighbours = [
      {gift, nil, [passed_on, sibling]},
      {passed_on, gift, [brought_in]},
      {brought_in, passed_on, []},
      {sibling, gift, []},
      {cancelled, gift, []}
    ]

    for {order, source, redemptions} <- neighbours do
      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

      if source do
        assert has_element?(view, ~s|#order-card-source a[href="/admin/orders/#{source.id}"]|)
      else
        refute has_element?(view, "#order-card-source")
      end

      for redemption <- redemptions do
        assert has_element?(view, ~s|#order-card-redemptions a[href="/admin/orders/#{redemption.id}"]|)
      end

      for unrelated <- [gift, passed_on, brought_in, sibling, cancelled, cart] -- (List.wrap(source) ++ redemptions) do
        refute has_element?(view, ~s|#order-pass-it-on a[href="/admin/orders/#{unrelated.id}"]|)
      end
    end

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{gift.id}")
    assert has_element?(view, "#order-card-outgoing")
  end

  test "a cancelled gift stays visible as the source of its redemption", %{conn: conn, admin: admin} do
    [code] = Edenflowers.Pricing.create_pass_it_on_batch!("Skicka vidare", 1, actor: admin)
    card = Edenflowers.Pricing.get_pass_it_on_card!(code, actor: admin)
    gift = placed_order(gift: true, fulfillment_status: :cancelled)
    Edenflowers.Pricing.link_card_to_gift_order!(card, gift.id, actor: admin)
    redemption = placed_order(promotion_id: card.id)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{redemption.id}")
    assert has_element?(view, ~s|#order-card-source a[href="/admin/orders/#{gift.id}"]|)
    assert has_element?(view, "#order-card-source", "Cancelled")
  end

  test "a redeemed unlinked card still shows its code and missing source", %{conn: conn} do
    [code] = Edenflowers.Pricing.create_pass_it_on_batch!("Skicka vidare", 1, actor: Edenflowers.Actors.system_actor())
    card = Edenflowers.Pricing.get_pass_it_on_card!(code, authorize?: false)
    order = placed_order(promotion_id: card.id)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
    assert has_element?(view, "#order-pass-it-on", code)
    assert has_element?(view, "#order-pass-it-on", "Source gift not linked")
    refute has_element?(view, "#link-card-form")

    manual = placed_order(promotion_id: generate(promotion()).id)
    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{manual.id}")
    refute has_element?(view, "#order-pass-it-on")
  end

  test "a card linked to an unplaced gift does not link to an inaccessible order", %{conn: conn, admin: admin} do
    [code] = Edenflowers.Pricing.create_pass_it_on_batch!("Skicka vidare", 1, actor: admin)
    card = Edenflowers.Pricing.get_pass_it_on_card!(code, actor: admin)
    cart = generate(order(gift: true))
    Edenflowers.Pricing.link_card_to_gift_order!(card, cart.id, actor: admin)
    redemption = placed_order(promotion_id: card.id)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{redemption.id}")
    assert has_element?(view, "#order-card-source", "Source gift not linked")
    refute has_element?(view, ~s|#order-card-source a[href="/admin/orders/#{cart.id}"]|)
  end

  test "external card changes warn and only appear after reloading the order",
       %{conn: conn, admin: admin} do
    [code] = Edenflowers.Pricing.create_pass_it_on_batch!("Skicka vidare", 1, actor: Edenflowers.Actors.system_actor())
    gift = placed_order(gift: true)
    Orders.link_pass_it_on_card!(gift, code, actor: admin)
    card = Edenflowers.Pricing.get_pass_it_on_card!(code, authorize?: false)
    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{gift.id}")
    assert has_element?(view, "#order-pass-it-on", "Not opened yet")

    card = Edenflowers.Pricing.start_promotion_validity!(card, actor: nil)
    assert has_element?(view, "#editor-stale-notice")
    assert has_element?(view, "#order-pass-it-on", "Not opened yet")
    {:ok, view, _} = live(conn, ~p"/admin/orders/#{gift.id}")
    assert has_element?(view, "#order-pass-it-on", "Opened")

    redeemed = placed_order(promotion_id: card.id, payment_intent_id: nil)
    Orders.update_florist_note!(redeemed, %{florist_note: "Flowers"}, actor: admin)
    assert has_element?(view, "#editor-stale-notice")
    refute has_element?(view, ~s|#order-card-redemptions a[href="/admin/orders/#{redeemed.id}"]|)
    {:ok, view, _} = live(conn, ~p"/admin/orders/#{gift.id}")
    assert has_element?(view, ~s|#order-card-redemptions a[href="/admin/orders/#{redeemed.id}"]|)
    refute has_element?(view, "#order-card-outgoing", "Opened")

    Orders.cancel_order!(redeemed, %{cancellation_reason: "Changed mind", email_customer?: false}, actor: admin)
    assert has_element?(view, "#editor-stale-notice")
    assert has_element?(view, "#order-card-redemption-#{redeemed.id}")
    {:ok, view, _} = live(conn, ~p"/admin/orders/#{gift.id}")
    refute has_element?(view, "#order-card-redemption-#{redeemed.id}")
    assert has_element?(view, "#order-card-outgoing", "Opened")

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{redeemed.id}")
    assert has_element?(view, ~s|#order-card-source a[href="/admin/orders/#{gift.id}"]|)
  end

  test "an expired card is distinguished from an opened usable card", %{conn: conn, admin: admin} do
    [code] = Edenflowers.Pricing.create_pass_it_on_batch!("Skicka vidare", 1, actor: Edenflowers.Actors.system_actor())
    gift = placed_order(gift: true)
    Orders.link_pass_it_on_card!(gift, code, actor: admin)
    card = Edenflowers.Pricing.get_pass_it_on_card!(code, authorize?: false)

    Edenflowers.Pricing.start_promotion_validity!(card, %{today: Date.add(Edenflowers.ShopTime.today(), -31)},
      actor: nil
    )

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{gift.id}")
    assert has_element?(view, "#order-card-outgoing", "Expired")
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

  test "a cancelled order with an unpaid cancellation charge offers no payment link", %{conn: conn, admin: admin} do
    order = placed_order(origin: :custom, payment_intent_id: nil)
    Orders.cancel_order!(order, %{cancellation_charge: "30.00", email_customer?: false}, actor: admin)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
    refute has_element?(view, ~s|button[phx-click="open_payment_link"]|)
  end

  # A voucher sale has no fulfillment date for its emails' previews to name.
  test "a gift voucher sold in the shop is paid in person, or cancelled", %{conn: conn, admin: admin} do
    {:ok, sale} =
      Orders.sell_gift_voucher(%{customer_name: "Anna", customer_email: "a@example.com", amount: 35}, actor: admin)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{sale.id}")
    refute has_element?(view, ~s|[phx-value-kind="order_details"]|)
    refute has_element?(view, ~s|[phx-value-kind="payment_reminder"]|)
    refute has_element?(view, ~s|button[phx-click="open_payment_link"]|)

    view |> element(~s|button[phx-click="open_settlement"]|) |> render_click()
    assert has_element?(view, "#order-balance-email-send[checked]")
    assert has_element?(view, ~s|#order-balance-method option[value="cash"]|)
    refute has_element?(view, ~s|#order-balance-method option[value="voucher"]|)

    view
    |> element("#order-balance-form")
    |> render_change(%{
      "_target" => ["payment", "amount"],
      "payment" => %{"payment_method" => "cash", "amount" => "20"}
    })

    refute has_element?(view, "#order-balance-email-send")
    assert has_element?(view, "#order-balance-voucher-later")

    view |> element(~s|button[phx-click="open_cancel"]|) |> render_click()
    view |> form("#cancel-form") |> render_submit()

    assert Orders.get_order_by_id!(sale.id, authorize?: false).fulfillment_status == :cancelled
  end

  test "an order on invoice terms is invoiced from its page, then shows the invoice and stays locked",
       %{conn: conn, admin: admin} do
    order = placed_order(origin: :custom, payment_terms: :invoice, payment_intent_id: nil)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
    assert {:error, {:live_redirect, %{to: "/admin/invoices/" <> invoice_id}}} = render_click(view, "create_invoice")

    {:ok, draft} = Edenflowers.Payments.get_invoice(invoice_id, actor: admin)
    {:ok, invoice} = Edenflowers.Payments.issue_invoice(draft, actor: admin)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
    assert has_element?(view, "#order-status", "Invoiced")
    assert has_element?(view, ~s|#order-invoices a[href="/admin/invoices/#{invoice.id}"]|, "Invoice #{invoice.number}")
    assert has_element?(view, "#order-invoices", "Unpaid")
    refute has_element?(view, ~s|button[phx-click="create_invoice"]|)
    assert has_element?(view, ~s|a[href="/admin/orders/#{order.id}/edit"]|)
    refute has_element?(view, ~s|button[phx-click="open_cancel"]|)
  end

  test "an order on other terms offers no invoice", %{conn: conn} do
    order = placed_order(origin: :custom, payment_terms: :payment_link, payment_intent_id: nil)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
    refute has_element?(view, ~s|button[phx-click="create_invoice"]|)
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
    assert has_element?(view, "#email-drawer-email-preview", "Your receipt from Eden Flowers")
    assert has_element?(view, "#email-drawer-email-preview", "Attached: eden-flowers-#{order.order_reference}.pdf")

    view |> form("#email-form", email: %{edit_email: "true"}) |> render_change()
    assert has_element?(view, "#email-drawer-email-subject[value^='Your receipt from Eden Flowers']")
    assert has_element?(view, "#email-drawer-email-body", "Hi Ada,")

    view |> form("#email-form", email: %{edit_email: "false"}) |> render_change()
    refute has_element?(view, "#email-drawer-email-editor")
    assert has_element?(view, "#email-drawer-email-preview", "Your receipt from Eden Flowers")

    assert_no_email_sent()
    refute_enqueued(worker: Edenflowers.Orders.Workers.SendReceiptEmail)
  end

  test "a bank-transfer order can receive its own payment reminder", %{conn: conn} do
    order = placed_order()

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
    assert has_element?(view, ~s|button[phx-value-kind="payment_reminder"]|, "Send payment reminder")

    Ash.Seed.update!(order, %{payment_terms: :invoice})

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
    assert has_element?(view, ~s|button[phx-value-kind="payment_reminder"]|)
  end

  test "the actions menu hides unavailable options", %{conn: conn} do
    order = placed_order(fulfillment_method: :delivery)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, ~s|#order-actions button[phx-value-kind="order_details"]|)
    assert has_element?(view, ~s|#order-actions button[phx-value-kind="payment_reminder"]|)
    assert has_element?(view, ~s|#order-actions button[phx-click="open_cancel"]|)
    refute has_element?(view, "#order-actions [aria-disabled=true]")
    refute has_element?(view, "#order-actions li", "Email confirmation")
    refute has_element?(view, "#order-actions li", "View receipt")
    refute has_element?(view, "#order-actions li", "Email receipt")
    refute has_element?(view, "#order-actions li", "Refund")
  end

  test "an order with no selectable menu options has no actions menu", %{conn: conn} do
    order = placed_order(customer_email: nil, customer_phone_number: "044 222 3344", fulfillment_status: :fulfilled)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    refute has_element?(view, ~s|button[aria-label="More actions"]|)
    refute has_element?(view, "#order-actions")
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
    order = placed_order(fulfillment_status: :ready)

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    refute has_element?(view, ~s|button[phx-value-kind="fulfillment"]|)
    view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
    refute has_element?(view, ~s|#confirm-fulfillment-form input[type="checkbox"]|)
    view |> form("#confirm-fulfillment-form") |> render_submit()

    refute has_element?(view, ~s|button[phx-click="confirm_fulfillment"]|)
    assert has_element?(view, "#order-status", "Fulfilled")
    assert render(view) =~ "Order marked as collected."
    assert_push_event(view, "order-fulfilled", %{})
    refute render(view) =~ "Confirmation queued."
    refute_enqueued(worker: Edenflowers.Orders.Workers.SendFulfillmentEmail)

    reloaded = Orders.get_order_for_admin!(order.id, actor: %{admin: true})
    assert reloaded.fulfillment_status == :fulfilled
  end

  test "a voucher to collect as a gift card shows what to write on it until it's collected", %{conn: conn} do
    {sale, voucher} = paid_voucher_sale(%{collect_voucher_card: true})

    {:ok, view, _html} = live(conn, ~p"/admin/orders")
    assert has_element?(view, "[data-item-id]", "Card to write")

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{sale.id}")
    assert has_element?(view, "#order-status", "Card to write")
    assert has_element?(view, "#order-gift-voucher-code", Edenflowers.Payments.GiftVoucher.format_code(voucher.code))

    view |> element("button", "Mark as ready") |> render_click()
    view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
    view |> form("#confirm-fulfillment-form") |> render_submit()

    assert has_element?(view, "#order-status", "Fulfilled")
    refute has_element?(view, "#order-status", "Card to write")
  end

  test "a voucher's order shows spending and preserves its date editor through refreshes", %{conn: conn, admin: admin} do
    {sale, voucher} = paid_voucher_sale()
    sale = Orders.get_order_for_admin!(sale.id, actor: admin)
    spent_on = placed_order(customer_name: "Bertil Ek")

    generate(
      payment(order_id: spent_on.id, gift_voucher_id: voucher.id, method: :voucher, amount: Decimal.new("20.00"))
    )

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{sale.id}")
    assert has_element?(view, "#order-gift-voucher-remaining", "30,00")
    assert has_element?(view, ~s|#order-gift-voucher-payments a[href="/admin/orders/#{spent_on.id}"]|, "Bertil Ek")

    later = Date.add(voucher.expires_on, 90)
    view |> form("#gift-voucher-last-day", voucher: %{expires_on: Date.to_iso8601(later)}) |> render_change()
    Orders.update_florist_note!(sale, %{florist_note: "Saved elsewhere"}, actor: admin)

    assert has_element?(view, "#gift-voucher-expires-on[value='#{later}']")
    assert has_element?(view, "#editor-stale-notice")

    earlier = Date.add(voucher.expires_on, -1)

    view
    |> form("#gift-voucher-last-day", voucher: %{expires_on: Date.to_iso8601(earlier)})
    |> render_submit()

    assert has_element?(view, "#gift-voucher-last-day", "must be later than the current last day")
    Orders.update_florist_note!(sale, %{florist_note: "Another saved note"}, actor: admin)
    assert has_element?(view, "#gift-voucher-expires-on[value='#{earlier}']")
    assert has_element?(view, "#gift-voucher-last-day", "must be later than the current last day")

    view
    |> form("#gift-voucher-last-day", voucher: %{expires_on: Date.to_iso8601(later)})
    |> render_submit()

    assert Ash.reload!(voucher, authorize?: false).expires_on == later
    refute has_element?(view, "#editor-stale-notice")
  end

  test "fulfills a pickup with no customer email", %{conn: conn} do
    order = placed_order(fulfillment_status: :ready, customer_email: nil, customer_phone_number: "044 222 3344")

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

    view |> form("#email-form", email: %{edit_email: "true"}) |> render_change()

    edited = %{edit_email: "true", subject: "Your flowers arrived", body: "Thank you for choosing us."}
    assert view |> form("#email-form", email: edited) |> render_submit() =~ "Confirmation queued."

    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :default)

    assert_email_sent(fn email ->
      assert email.subject == "Your flowers arrived"
      assert email.text_body == "Thank you for choosing us."
    end)

    assert has_element?(view, "#editor-stale-notice")
    {:ok, view, _} = live(conn, ~p"/admin/orders/#{order.id}")
    assert has_element?(view, "#order-log li", ~r/Delivered email sent.*Your flowers arrived/s)
    assert has_element?(view, "#order-log li", ~r/Delivered email sent.*Thank you for choosing us\./s)
    assert has_element?(view, "#order-log li", ~r/Delivered email sent.*ada@example\.com/s)
    assert has_element?(view, ~s|button[phx-value-kind="fulfillment"]|, "Resend confirmation")

    order |> Ash.reload!(authorize?: false) |> Ash.Seed.update!(%{customer_email: "new@example.com"})
    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, "#order-log li", ~r/Delivered email sent.*ada@example\.com/s)
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
    assert has_element?(view, "#editor-stale-notice")
    refute has_element?(view, "#order-confirmation-failed")
    {:ok, view, _} = live(conn, ~p"/admin/orders/#{order.id}")
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
    assert has_element?(view, "#editor-stale-notice")
    refute has_element?(view, "#order-email-failed")
    {:ok, view, _} = live(conn, ~p"/admin/orders/#{order.id}")
    assert has_element?(view, "#order-email-failed", "Couldn't email the receipt.")
    assert has_element?(view, "#order-log li", "Receipt failed")
  end

  describe "confirming a delivery" do
    test "reopening after native drawer dismissal forgets the previous photo", %{conn: conn} do
      order = placed_order(fulfillment_status: :ready, fulfillment_method: :delivery)
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
      assert Orders.get_order_for_admin!(order.id, actor: %{admin: true}).fulfillment_status == :ready
      refute_enqueued(worker: Edenflowers.Orders.Workers.SendFulfillmentEmail)
    end

    test "the customer was home: fulfils with no photo and, by default, no email", %{conn: conn} do
      order = placed_order(fulfillment_status: :ready, fulfillment_method: :delivery)

      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

      view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
      assert has_element?(view, "#confirm-fulfillment-form label", "Email delivery confirmation")
      assert has_element?(view, "#confirm-fulfillment-form", "To: ada@example.com")
      view |> form("#confirm-fulfillment-form", fulfillment: %{customer_home: "true"}) |> render_change()
      refute has_element?(view, ~s|#confirm-fulfillment-form input[name="fulfillment[email_customer?]"][checked]|)
      refute has_element?(view, "#confirm-fulfillment-form input[type=file]")
      view |> form("#confirm-fulfillment-form") |> render_submit()

      assert has_element?(view, "#order-status", "Fulfilled")
      refute has_element?(view, "#order-delivery-photo")
      refute_enqueued(worker: Edenflowers.Orders.Workers.SendFulfillmentEmail)
    end

    test "nobody was home: requires a photo, then names it after the time and order reference", %{conn: conn} do
      order = placed_order(fulfillment_status: :ready, fulfillment_method: :delivery)

      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
      view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
      view |> form("#confirm-fulfillment-form", fulfillment: %{customer_home: "false"}) |> render_change()

      view |> form("#confirm-fulfillment-form") |> render_submit()
      assert has_element?(view, "#confirm-fulfillment-dialog [role=alert]", "Take a photo of where you left the order.")
      assert Orders.get_order_for_admin!(order.id, actor: %{admin: true}).fulfillment_status == :ready

      view
      |> file_input("#confirm-fulfillment-form", "photo_fulfillment[photo]", [
        %{name: "IMG_0001.JPG", content: "jpeg bytes", type: "image/jpeg"}
      ])
      |> render_upload("IMG_0001.JPG")

      view |> form("#confirm-fulfillment-form", fulfillment: %{email_customer?: "false"}) |> render_submit()

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
      order = placed_order(fulfillment_status: :ready, fulfillment_method: :delivery, locale: "en-GB")
      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
      view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
      view |> form("#confirm-fulfillment-form", fulfillment: %{customer_home: "false"}) |> render_change()
      assert has_element?(view, "#fulfillment-email-preview", "was left at the door")
      assert has_element?(view, "#fulfillment-email-preview", "Attached: eden-flowers-delivery.jpg")

      view |> form("#confirm-fulfillment-form", fulfillment: %{email_customer?: "false"}) |> render_change()
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
      order = placed_order(fulfillment_status: :ready, fulfillment_method: :delivery)

      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
      view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
      assert_push_event(view, "js-exec", %{to: "#confirm-fulfillment", attr: "phx-show"})
      assert has_element?(view, "#confirm-fulfillment-form label", "Email delivery confirmation")
      refute has_element?(view, ~s|#confirm-fulfillment-form input[name="fulfillment[email_customer?]"][checked]|)

      view |> form("#confirm-fulfillment-form", fulfillment: %{email_customer?: "true"}) |> render_change()
      assert has_element?(view, ~s|#confirm-fulfillment-form input[name="fulfillment[email_customer?]"][checked]|)

      view |> element("#confirm-fulfillment-form button", "Cancel") |> render_click()
      view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
      refute has_element?(view, ~s|#confirm-fulfillment-form input[name="fulfillment[email_customer?]"][checked]|)
    end

    test "a gift, or a delivery left while nobody was home, starts ticked", %{conn: conn} do
      checked = ~s|#confirm-fulfillment-form input[name="fulfillment[email_customer?]"][checked]|

      gift =
        placed_order(
          fulfillment_status: :ready,
          fulfillment_method: :delivery,
          gift: true,
          recipient_name: "Grace Hopper"
        )

      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{gift.id}")
      view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
      assert has_element?(view, checked)
      view |> form("#confirm-fulfillment-form", fulfillment: %{customer_home: "true"}) |> render_change()
      assert has_element?(view, checked)

      order = placed_order(fulfillment_status: :ready, fulfillment_method: :delivery)
      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
      view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()
      view |> form("#confirm-fulfillment-form", fulfillment: %{customer_home: "false"}) |> render_change()
      assert has_element?(view, checked)
    end

    test "no: fulfils without queueing the fulfillment email", %{conn: conn} do
      # Gift orders select the fulfillment email by default, so unticking explicitly opts out.
      order =
        placed_order(
          fulfillment_status: :ready,
          fulfillment_method: :delivery,
          gift: true,
          recipient_name: "Grace Hopper"
        )

      {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
      view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()

      view |> form("#confirm-fulfillment-form", fulfillment: %{customer_home: "true"}) |> render_change()

      view
      |> form("#confirm-fulfillment-form", fulfillment: %{customer_home: "true", email_customer?: "false"})
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

    {html, log} =
      ExUnit.CaptureLog.with_log(fn -> refund_from_page(view, %{amount: "100", payment_method: "stripe"}) end)

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
    refund_from_page(view, %{amount: "20", payment_method: "stripe"})

    assert has_element?(view, "#order-log", "Refunded 10,00 € · Stripe")
    assert has_element?(view, "#order-log", "Refunded 20,00 € · Stripe")
  end

  test "offers ready-for-pickup message links in the customer's language", %{conn: conn} do
    order =
      placed_order(
        order_reference: "DETAIL",
        customer_phone_number: "040 123 4567",
        locale: "sv-FI",
        fulfillment_status: :ready
      )

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    body = "Hej%20Ada%2C%20din%20best%C3%A4llning%20DETAIL"
    assert has_element?(view, ~s|#order-ready-messages a[href^="sms:+358401234567?&body=#{body}"]|)
    assert has_element?(view, ~s|#order-ready-messages a[href^="https://wa.me/358401234567?text=#{body}"]|)
  end

  test "omits ready-for-pickup links for deliveries, unprepared and fulfilled pickups", %{conn: conn} do
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

    for order <- [delivery, fulfilled, placed_order(customer_phone_number: "040 123 4567")] do
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

    assert has_element?(view, "#order-queue-nav", "2 of 3")
    assert has_element?(view, ~s|#order-queue-nav a[href="/admin/orders/#{earlier.id}"]|)
    assert has_element?(view, ~s|#order-queue-nav a[href="/admin/orders/#{later.id}"]|)
  end

  test "keeps stepping after marking an order fulfilled and counts what is left", %{conn: conn} do
    current = placed_order(fulfillment_status: :ready, order_reference: "CURRENT", fulfillment_date: ~D[2026-06-11])
    later = placed_order(order_reference: "LATER", fulfillment_date: ~D[2026-06-12])
    placed_order(order_reference: "LATEST", fulfillment_date: ~D[2026-06-13])

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{current.id}")

    view
    |> element(~s|button[phx-click="confirm_fulfillment"]|)
    |> render_click()

    view |> form("#confirm-fulfillment-form") |> render_submit()

    assert has_element?(view, "#order-queue-nav", "Fulfilled · 2 left")
    refute has_element?(view, "#order-queue-nav", "1 of 3")
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
    for method <- [:cash, :zettle], kind <- [:flowers, :gift_voucher] do
      @refund_method method
      @order_kind kind
      test "a cancelled #{@order_kind} order paid by #{@refund_method} uses the standard refund flow", %{
        conn: conn,
        admin: admin
      } do
        order =
          case @order_kind do
            :flowers ->
              placed_order(payment_intent_id: nil)

            :gift_voucher ->
              Orders.sell_gift_voucher!(
                %{customer_name: "Anna", customer_email: "a@example.com", amount: 50, locale: "en-GB"},
                actor: admin
              )
          end

        order = Orders.record_payment!(order, "50.00", @refund_method, actor: admin)
        {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

        if @order_kind == :gift_voucher do
          refute has_element?(view, "#order-actions button", "Refund")
          assert has_element?(view, ~s|[phx-value-kind="gift_voucher"]|)
        end

        view |> element(~s|button[phx-click="open_cancel"]|) |> render_click()
        view |> form("#cancel-form", cancel: %{email_customer?: "false"}) |> render_submit()

        assert has_element?(view, "#order-balance", "To refund")
        assert has_element?(view, "#order-actions button", "Refund")
        refute has_element?(view, "#order-status", "Refunded")

        if @order_kind == :gift_voucher do
          refute has_element?(view, ~s|[phx-value-kind="gift_voucher"]|)
          cancelled = Orders.get_order_for_admin!(order.id, actor: admin)
          assert {:error, _} = Orders.email_gift_voucher(cancelled, actor: admin)
        end

        view |> element("#order-balance-settle") |> render_click()
        assert has_element?(view, ~s|#order-refund-amount[value="50.00"]|)
        assert has_element?(view, ~s|#order-refund-how option[value="#{@refund_method}"][selected]|)

        assert view
               |> form("#order-refund-form",
                 refund: %{amount: "50.00", payment_method: to_string(@refund_method), email_customer?: "true"}
               )
               |> render_submit() =~ "Refund recorded."

        assert has_element?(view, "#order-status", "Refunded")
        assert has_element?(view, "#order-payments", "Refund")
        assert has_element?(view, "#order-log", "Refunded")
        refute has_element?(view, "#order-balance")
        refute has_element?(view, "#order-actions button", "Refund")

        order = Orders.get_order_for_admin!(order.id, actor: admin)
        assert order.fulfillment_status == :cancelled
        assert order.payment_status == :refunded
        assert Decimal.eq?(order.balance, 0)

        [job] = all_enqueued(worker: Edenflowers.Payments.Workers.SendRefundedEmail)
        assert :ok = perform_job(Edenflowers.Payments.Workers.SendRefundedEmail, job.args)

        assert_email_sent(fn email ->
          if @order_kind == :gift_voucher do
            assert email.subject == "A refund for your Eden Flowers gift voucher"
          end

          assert email.text_body =~ order.order_reference
        end)
      end
    end

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
      refund_from_page(view, %{amount: "20,00", payment_method: "cash", note: "Wilted early"})

      assert has_element?(view, "#order-log", "Refunded 20,00 € · Cash")
      assert has_element?(view, "#order-log", "Wilted early")
      assert has_element?(view, "#order-payments", "Refund · Cash")
      refute render(view) =~ "To collect"
      assert [_job] = all_enqueued(worker: Edenflowers.Payments.Workers.SendRefundedEmail)
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

  # A 50 € voucher sale paid at checkout, and the voucher it issued.
  defp paid_voucher_sale(attrs \\ %{}) do
    sale =
      Orders.start_gift_voucher_sale!(
        50,
        Map.merge(
          %{
            customer_name: "Anna Buyer",
            customer_email: "anna@example.com",
            recipient_name: "Mia",
            locale: "sv-FI",
            voucher_locale: "fi"
          },
          attrs
        ),
        actor: nil
      )

    Mox.expect(StripeAPI.Mock, :create_payment_intent, fn 5000, _metadata, nil ->
      {:ok, %{id: "pi_#{sale.id}", client_secret: "pi_secret", amount: 5000}}
    end)

    {:ok, _} = Orders.prepare_checkout_payment(sale.id, actor: nil)

    {:ok, :completed} =
      Edenflowers.Payments.complete(%{
        id: "pi_#{sale.id}",
        status: "succeeded",
        metadata: %{"order_id" => sale.id},
        amount_received: 5000
      })

    [%{gift_voucher: voucher}] = Ash.load!(sale, [line_items: :gift_voucher], authorize?: false).line_items
    {sale, voucher}
  end
end
