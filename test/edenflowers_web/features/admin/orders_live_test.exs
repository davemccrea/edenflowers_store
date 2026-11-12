defmodule EdenflowersWeb.Admin.OrdersLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  setup :log_in_admin

  test "shows flowers or gift vouchers alone", %{conn: conn} do
    placed_order(customer_name: "Ada Lovelace")
    voucher_sale = placed_order(customer_name: "Grace Hopper")

    Ash.Seed.seed!(Edenflowers.Orders.LineItem, %{
      order_id: voucher_sale.id,
      is_gift_voucher: true,
      unit_price: Decimal.new("50.00"),
      tax_rate: Decimal.new(0),
      product_name: "Gift voucher"
    })

    {:ok, view, _html} = live(conn, ~p"/admin/orders?kind=gift_vouchers")
    assert has_element?(view, "[data-item-id]", "Grace Hopper")
    refute has_element?(view, "[data-item-id]", "Ada Lovelace")

    {:ok, view, _html} = live(conn, ~p"/admin/orders?kind=flowers")
    assert has_element?(view, "[data-item-id]", "Ada Lovelace")
    refute has_element?(view, "[data-item-id]", "Grace Hopper")
  end

  test "searches orders by order reference as well as customer name", %{conn: conn} do
    placed_order(order_reference: "ABC123", customer_name: "Ada Lovelace")
    placed_order(order_reference: "XYZ789", customer_name: "Grace Hopper")

    {:ok, view, _html} = live(conn, ~p"/admin/orders?search=abc1")

    assert has_element?(view, "[data-item-id]", "Ada Lovelace")
    refute has_element?(view, "[data-item-id]", "Grace Hopper")

    {:ok, view, _html} = live(conn, ~p"/admin/orders?search=grace")

    assert has_element?(view, "[data-item-id]", "Grace Hopper")
    refute has_element?(view, "[data-item-id]", "Ada Lovelace")
  end

  test "shows only gift orders, done or not", %{conn: conn} do
    placed_order(customer_name: "Gift Giver", gift: true, recipient_name: "Anna", fulfillment_status: :fulfilled)
    placed_order(customer_name: "For Myself")

    {:ok, view, _html} = live(conn, ~p"/admin/orders?open=gift")

    assert has_element?(view, "[data-item-id]", "Gift Giver")
    refute has_element?(view, "[data-item-id]", "For Myself")
  end

  test "filters prepared and unprepared orders without treating ready as done", %{conn: conn} do
    pending = placed_order(customer_name: "Still making", paid: true)
    ready = placed_order(customer_name: "Prepared", fulfillment_status: :ready, paid: true)
    done = placed_order(customer_name: "Done", fulfillment_status: :fulfilled, paid: true)
    ids = [pending.id, ready.id, done.id]

    for {filter, expected} <- [
          {"pending", [pending.id]},
          {"ready", [ready.id]},
          {"unfinished", [pending.id, ready.id]},
          {"true", [pending.id, ready.id]}
        ] do
      {:ok, view, _html} = live(conn, ~p"/admin/orders?open=#{filter}")

      for id <- ids do
        assert has_element?(view, ~s|[data-item-id="#{id}"]|) == id in expected
      end

      if ready.id in expected do
        assert has_element?(view, ~s|[data-item-id="#{ready.id}"]|, "Ready for pickup")
      end
    end
  end

  test "opens on the orders still to make or still to be paid for", %{conn: conn} do
    placed_order(customer_name: "To Make", paid: true, fulfillment_status: :pending)
    placed_order(customer_name: "Already Done", paid: true, fulfillment_status: :fulfilled)
    placed_order(customer_name: "Pays Later", fulfillment_status: :pending)
    placed_order(customer_name: "Delivered Unpaid", fulfillment_status: :fulfilled)
    placed_order(customer_name: "Called Off", fulfillment_status: :cancelled)

    {:ok, view, _html} = live(conn, ~p"/admin/orders")

    assert has_element?(view, "[data-item-id]", "To Make")
    assert has_element?(view, "[data-item-id]", "Pays Later")
    assert has_element?(view, "[data-item-id]", "Delivered Unpaid")
    refute has_element?(view, "[data-item-id]", "Already Done")
    refute has_element?(view, "[data-item-id]", "Called Off")
    assert has_element?(view, ~s(nav a[aria-current="page"]), "Orders")
  end

  test "shows an order placed elsewhere without a refresh", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/orders")

    refute has_element?(view, "[data-item-id]", "Grace Hopper")
    placed_order(customer_name: "Grace Hopper")

    EdenflowersWeb.Endpoint.broadcast("admin:orders", "finalize_checkout", %{})

    eventually(fn ->
      render_async(view, 500)
      assert has_element?(view, "[data-item-id]", "Grace Hopper")
    end)
  end

  test "lists every placed order once the default filter is cleared", %{conn: conn} do
    placed_order(customer_name: "To Make", paid: true, fulfillment_status: :pending)
    placed_order(customer_name: "Already Done", paid: true, fulfillment_status: :fulfilled)
    placed_order(customer_name: "Called Off", origin: :custom, fulfillment_status: :cancelled)

    {:ok, view, _html} = live(conn, ~p"/admin/orders")
    render_patch(view, ~p"/admin/orders")

    assert has_element?(view, "[data-item-id]", "To Make")
    assert has_element?(view, "[data-item-id]", "Already Done")
    assert has_element?(view, "[data-item-id]", "Called Off")
  end

  test "a cancelled custom order stays searchable and directly accessible, with late money visible in Overview", %{
    conn: conn
  } do
    order = placed_order(origin: :custom, fulfillment_status: :cancelled, order_reference: "CANCELLED123")
    {:ok, view, _html} = live(conn, ~p"/admin/orders")
    refute has_element?(view, ~s|[data-item-id="#{order.id}"]|)

    ExUnit.CaptureLog.capture_log(fn ->
      assert {:ok, :completed} =
               Edenflowers.Payments.complete(%{
                 id: "pi_late_filtered",
                 metadata: %{"order_id" => order.id},
                 amount_received: 8_850
               })
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/orders?search=CANCELLED123")
    assert has_element?(view, ~s|[data-item-id="#{order.id}"]|)
    {:ok, view, _html} = live(conn, ~p"/admin/search?q=CANCELLED123")
    render_async(view)
    assert has_element?(view, ~s|a[href="/admin/orders/#{order.id}"]|)
    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
    assert render(view) =~ "To refund"
    refute has_element?(view, ~s|button[phx-click="delete_order"]|)
    {:ok, view, _html} = live(conn, ~p"/admin")
    assert has_element?(view, "#attention-refund summary", "To refund")
    assert has_element?(view, ~s|#attention-refund a[href="/admin/orders/#{order.id}"]|)
  end

  test "filtering by unpaid lists orders still owed for, fulfilled or not", %{conn: conn} do
    placed_order(customer_name: "Paid Up", paid: true, fulfillment_status: :pending)

    placed_order(customer_name: "Delivered Unpaid", fulfillment_status: :fulfilled)

    {:ok, view, _html} = live(conn, ~p"/admin/orders?payment_status=pending")

    assert has_element?(view, "[data-item-id]", "Delivered Unpaid")
    refute has_element?(view, "[data-item-id]", "Paid Up")
  end

  test "flags orders still to fulfil whose fulfillment date has passed", %{conn: conn} do
    last_week = Date.add(Edenflowers.ShopTime.today(), -7)
    late = placed_order(customer_name: "Late", fulfillment_date: last_week, fulfillment_status: :pending)
    done = placed_order(customer_name: "Done", fulfillment_date: last_week, fulfillment_status: :fulfilled)

    {:ok, view, _html} = live(conn, ~p"/admin/orders")

    assert has_element?(view, ~s([data-item-id="#{late.id}"]), "Overdue")
    refute has_element?(view, ~s([data-item-id="#{done.id}"]), "Overdue")
  end

  test "flags orders with money still to collect", %{conn: conn} do
    mismatched = placed_order(customer_name: "Mismatched", paid: "0.01")
    matching = placed_order(customer_name: "Matching", paid: true)

    {:ok, view, _html} = live(conn, ~p"/admin/orders")

    assert has_element?(view, ~s([data-item-id="#{mismatched.id}"]), "To collect")
    refute has_element?(view, ~s([data-item-id="#{matching.id}"]), "To collect")
  end

  test "marks orders a subscription created", %{conn: conn} do
    occurrence = placed_order(customer_name: "Subscriber", origin: :subscription)
    online = placed_order(customer_name: "Shopper")

    {:ok, view, _html} = live(conn, ~p"/admin/orders")

    assert has_element?(view, ~s([data-item-id="#{occurrence.id}"]), "Subscription")
    refute has_element?(view, ~s([data-item-id="#{online.id}"]), "Subscription")
  end

  # The filter offers whatever the enum holds, so a new status must get a label.
  test "labels every payment status" do
    for status <- Edenflowers.Orders.Order.Types.PaymentStatus.values() do
      assert EdenflowersWeb.Admin.Components.payment_status_label(status) != to_string(status)
    end
  end
end
