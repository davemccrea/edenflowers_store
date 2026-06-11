defmodule EdenflowersWeb.Webhooks.StripeHandlerTest do
  use Edenflowers.DataCase

  import ExUnit.CaptureLog
  import Generator
  import Swoosh.TestAssertions

  alias Edenflowers.Orders.Order

  alias Edenflowers.Orders

  setup do
    Edenflowers.Repo.delete_all(Oban.Job)

    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    product_variant = generate(product_variant(product_id: product.id))
    fulfillment_option = generate(fulfillment_option(tax_rate_id: tax_rate.id))

    {:ok, %{fulfillment_fee: fulfillment_fee}} =
      Edenflowers.Fulfillment.calculate_price(fulfillment_option.id, 0)

    {:ok, user} =
      Edenflowers.Accounts.upsert_user("john.smith@example.com", "John Smith", authorize?: false)

    order =
      Ash.Seed.seed!(Order, %{
        order_reference: :crypto.strong_rand_bytes(6) |> Base.encode16(),
        state: :payment,
        customer_name: "John Smith",
        customer_email: "john.smith@example.com",
        user_id: user.id,
        fulfillment_option_id: fulfillment_option.id,
        fulfillment_date: Date.utc_today(),
        fulfillment_fee: fulfillment_fee,
        payment_intent_id: "pi_test_#{:rand.uniform(1_000_000)}"
      })

    _line_item =
      generate(
        line_item(
          order_id: order.id,
          product_variant_id: product_variant.id,
          quantity: 1
        )
      )

    %{order: order}
  end

  describe "payment_intent.succeeded" do
    test "finalizes the order, marks it paid, and enqueues a confirmation email", %{order: order} do
      assert :ok =
               EdenflowersWeb.Webhooks.StripeHandler.handle_event(%Stripe.Event{
                 id: "evt_succeeded_1",
                 type: "payment_intent.succeeded",
                 data: %{object: %{metadata: %{"order_id" => order.id}}}
               })

      order = Orders.get_order_by_id!(order.id, authorize?: false)
      assert order.state == :placed
      assert order.payment_status == :paid

      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :default)

      assert_email_sent()
    end

    test "is idempotent on redelivery for an already-placed order", %{order: order} do
      event = %Stripe.Event{
        id: "evt_succeeded_dup",
        type: "payment_intent.succeeded",
        data: %{object: %{metadata: %{"order_id" => order.id}}}
      }

      # First delivery — finalizes + enqueues.
      assert :ok = EdenflowersWeb.Webhooks.StripeHandler.handle_event(event)
      # Stripe redelivers the same event after we've already processed it. The
      # handler must still return :ok so Stripe stops retrying, and the unique
      # constraint on the worker collapses the duplicate enqueue.
      assert :ok = EdenflowersWeb.Webhooks.StripeHandler.handle_event(event)

      order = Orders.get_order_by_id!(order.id, authorize?: false)
      assert order.state == :placed
      assert order.payment_status == :paid

      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :default)
    end

    test "returns :error when metadata.order_id is missing" do
      capture_log(fn ->
        assert :error =
                 EdenflowersWeb.Webhooks.StripeHandler.handle_event(%Stripe.Event{
                   id: "evt_no_metadata",
                   type: "payment_intent.succeeded",
                   data: %{object: %{metadata: %{}}}
                 })
      end)

      assert %{success: 0, failure: 0} = Oban.drain_queue(queue: :default)
      refute_email_sent()
    end
  end

  describe "payment_intent.payment_failed" do
    test "marks the order's payment_status as :failed without finalizing", %{order: order} do
      assert :ok =
               EdenflowersWeb.Webhooks.StripeHandler.handle_event(%Stripe.Event{
                 id: "evt_failed_1",
                 type: "payment_intent.payment_failed",
                 data: %{object: %{metadata: %{"order_id" => order.id}}}
               })

      order = Orders.get_order_by_id!(order.id, authorize?: false)
      assert order.state == :payment
      assert order.payment_status == :failed

      refute_email_sent()
    end

    test "does not downgrade an already-paid order", %{order: order} do
      # Succeeded fires first.
      assert :ok =
               EdenflowersWeb.Webhooks.StripeHandler.handle_event(%Stripe.Event{
                 id: "evt_first_success",
                 type: "payment_intent.succeeded",
                 data: %{object: %{metadata: %{"order_id" => order.id}}}
               })

      # A late `payment_failed` for the same intent shouldn't flip the order back.
      assert :ok =
               EdenflowersWeb.Webhooks.StripeHandler.handle_event(%Stripe.Event{
                 id: "evt_late_failure",
                 type: "payment_intent.payment_failed",
                 data: %{object: %{metadata: %{"order_id" => order.id}}}
               })

      order = Orders.get_order_by_id!(order.id, authorize?: false)
      assert order.state == :placed
      assert order.payment_status == :paid
    end
  end

  describe "payment_intent.canceled" do
    test "marks the order's payment_status as :failed", %{order: order} do
      assert :ok =
               EdenflowersWeb.Webhooks.StripeHandler.handle_event(%Stripe.Event{
                 id: "evt_canceled_1",
                 type: "payment_intent.canceled",
                 data: %{object: %{metadata: %{"order_id" => order.id}}}
               })

      order = Orders.get_order_by_id!(order.id, authorize?: false)
      assert order.state == :payment
      assert order.payment_status == :failed
    end
  end

  describe "unhandled events" do
    test "returns :ok for charge.succeeded (handled via payment_intent.succeeded)" do
      assert :ok =
               EdenflowersWeb.Webhooks.StripeHandler.handle_event(%Stripe.Event{
                 id: "evt_charge_succeeded",
                 type: "charge.succeeded",
                 data: %{object: %{}}
               })
    end

    test "returns :ok for an unhandled event type" do
      capture_log(fn ->
        assert :ok =
                 EdenflowersWeb.Webhooks.StripeHandler.handle_event(%Stripe.Event{
                   id: "evt_random",
                   type: "invoice.paid",
                   data: %{object: %{}}
                 })
      end)
    end
  end
end
