defmodule Edenflowers.Orders.OrderReadinessTest do
  use Edenflowers.DataCase, async: true

  import Generator
  import Swoosh.TestAssertions

  alias Edenflowers.Orders
  alias Edenflowers.ShopTime

  test "an unpaid order can be prepared and undone without changing money or notifying anyone" do
    admin = generate(admin_user())
    order = placed_order(fulfillment_date: ShopTime.today(), payment_terms: :on_fulfillment)
    original = Orders.get_order_for_admin!(order.id, actor: admin)

    assert {:ok, ready} = Orders.mark_order_ready(order, actor: admin)
    assert ready.fulfillment_status == :ready
    assert ready.ready_at
    assert ready.fulfillable?
    assert ready.cancellable?
    refute ready.editable?
    assert Decimal.equal?(ready.balance, original.balance)
    assert ready.to_collect?
    assert Enum.any?(Orders.list_orders_due_soon!(actor: admin), &(&1.id == order.id))
    assert Enum.any?(Orders.list_orders_to_fulfil!(actor: admin), &(&1.id == order.id))
    assert [] = all_enqueued()
    assert_no_email_sent()

    assert {:ok, undone} = Orders.undo_order_ready(ready, actor: admin)
    assert undone.fulfillment_status == :pending
    assert is_nil(undone.ready_at)
    assert undone.editable?
    assert Decimal.equal?(undone.balance, original.balance)
    assert [] = all_enqueued()
  end

  test "only admins may mark or undo readiness" do
    order = placed_order()
    customer = generate(admin_user(admin: false))
    assert {:error, %Ash.Error.Forbidden{}} = Orders.mark_order_ready(order, actor: customer)
    ready = Orders.mark_order_ready!(order, actor: generate(admin_user()))
    assert {:error, %Ash.Error.Forbidden{}} = Orders.undo_order_ready(ready, actor: customer)
  end

  test "stale requests cannot prepare or undo orders that have moved on" do
    admin = generate(admin_user())
    order = placed_order()
    ready = Orders.mark_order_ready!(order, actor: admin)
    assert {:error, _} = Orders.mark_order_ready(order, actor: admin)

    Orders.mark_order_fulfilled!(ready, %{email_customer?: false}, actor: admin)
    assert {:error, _} = Orders.undo_order_ready(ready, actor: admin)
    assert {:error, _} = Orders.mark_order_ready(order, actor: admin)
    assert Orders.get_order_by_id!(order.id, actor: admin).fulfillment_status == :fulfilled
  end

  test "handover requires readiness and cancellation remains available before handover" do
    admin = generate(admin_user())

    for status <- [:pending, :ready] do
      order = placed_order(fulfillment_status: status)

      if status == :ready do
        assert {:ok, %{fulfillment_status: :fulfilled}} =
                 Orders.mark_order_fulfilled(order, %{email_customer?: false}, actor: admin)
      else
        assert {:error, _} = Orders.mark_order_fulfilled(order, %{email_customer?: false}, actor: admin)
        assert Orders.get_order_by_id!(order.id, actor: admin).fulfillment_status == :pending
        assert [] = all_enqueued()
      end

      order = placed_order(fulfillment_status: status, payment_intent_id: nil)

      assert {:ok, %{fulfillment_status: :cancelled}} =
               Orders.cancel_order(order, %{email_customer?: false}, actor: admin)
    end
  end

  test "a stale ready order cannot be handed over after readiness is undone" do
    admin = generate(admin_user())
    ready = Orders.mark_order_ready!(placed_order(), actor: admin)
    Orders.undo_order_ready!(ready, actor: admin)

    assert {:error, _} = Orders.mark_order_fulfilled(ready, %{email_customer?: false}, actor: admin)
    assert Orders.get_order_by_id!(ready.id, actor: admin).fulfillment_status == :pending
    assert [] = all_enqueued()
  end

  test "carts, cancelled orders and fulfilled orders cannot be marked ready" do
    admin = generate(admin_user())
    cart = generate(order())
    assert {:error, _} = Orders.mark_order_ready(cart, actor: admin)

    for status <- [:cancelled, :fulfilled] do
      order = placed_order(fulfillment_status: status)
      assert {:error, _} = Orders.mark_order_ready(order, actor: admin)
      assert {:error, _} = Orders.undo_order_ready(order, actor: admin)
    end
  end

  test "a ready order that was never handed over is still overdue and open" do
    order = placed_order(fulfillment_status: :ready, fulfillment_date: Date.add(ShopTime.today(), -1), paid: true)
    order = Ash.load!(order, [:overdue?, :open?], authorize?: false)
    assert order.overdue?
    assert order.open?
  end

  test "pickup messaging is available only for a prepared pickup with a phone number" do
    admin = generate(admin_user())

    for {method, phone, sendable?} <- [
          {:pickup, "+358401234567", true},
          {:pickup, nil, false},
          {:delivery, "+358401234567", false}
        ] do
      order = placed_order(fulfillment_method: method, customer_phone_number: phone)
      refute Orders.get_order_for_admin!(order.id, actor: admin).pickup_message_sendable?

      ready = Orders.mark_order_ready!(order, actor: admin)
      assert ready.pickup_message_sendable? == sendable?

      undone = Orders.undo_order_ready!(ready, actor: admin)
      refute undone.pickup_message_sendable?
      ready = Orders.mark_order_ready!(undone, actor: admin)
      fulfilled = Orders.mark_order_fulfilled!(ready, %{email_customer?: false}, actor: admin)
      refute fulfilled.pickup_message_sendable?
    end
  end

  test "admin list scopes are enforced by the read action, without a LiveView" do
    admin = generate(admin_user())
    pending = placed_order(customer_name: "To make", paid: true)
    ready = placed_order(fulfillment_status: :ready, gift: true)
    unpaid = placed_order(fulfillment_status: :fulfilled)
    done = placed_order(fulfillment_status: :fulfilled, paid: true)
    cancelled = placed_order(fulfillment_status: :cancelled)
    generate(order())

    for {show, expected} <- [
          {"all", [pending.id, ready.id, unpaid.id, done.id, cancelled.id]},
          {"true", [pending.id, ready.id, unpaid.id]},
          {"unfinished", [pending.id, ready.id]},
          {"pending", [pending.id]},
          {"ready", [ready.id]},
          {"gift", [ready.id]}
        ] do
      results = Orders.list_orders_for_admin!(%{show: show}, actor: admin, page: false)
      assert Enum.sort(Enum.map(results, & &1.id)) == Enum.sort(expected)
    end

    assert [%{id: id}] =
             Orders.list_orders_for_admin!(%{show: "pending", term: "to MAKE", kind: "flowers"},
               actor: admin,
               page: false
             )

    assert id == pending.id
    assert [] = Orders.list_orders_for_admin!(%{kind: "gift_vouchers"}, actor: admin, page: false)
  end

  test "ready and undo are recorded in the order history" do
    admin = generate(admin_user())
    order = placed_order()
    ready = Orders.mark_order_ready!(order, actor: admin)
    Orders.undo_order_ready!(ready, actor: admin)
    order = Ash.load!(order, :paper_trail_versions, authorize?: false)
    actions = Enum.map(order.paper_trail_versions, & &1.version_action_name)
    assert :mark_ready in actions
    assert :undo_ready in actions
  end
end
