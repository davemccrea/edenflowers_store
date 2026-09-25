defmodule Edenflowers.Orders.PaymentTest do
  use Edenflowers.DataCase, async: true

  import Generator
  import Mox

  import ExUnit.CaptureLog

  alias Edenflowers.Orders
  alias Edenflowers.Orders.Payment

  setup :verify_on_exit!

  describe "setup_payment/2" do
    test "creates and persists a payment intent when the order has none" do
      order = generate(order(state: :payment))
      payment_intent = %{id: "pi_new", client_secret: "pi_new_secret"}

      expect(Edenflowers.External.StripeAPI.Mock, :create_payment_intent, fn ^order ->
        {:ok, payment_intent}
      end)

      assert {:ok, updated_order, "pi_new_secret"} = Payment.setup_payment(order, nil)
      assert updated_order.payment_intent_id == "pi_new"
    end

    test "retrieves an existing payment intent" do
      order = generate(order(state: :payment, payment_intent_id: "pi_existing"))
      payment_intent = %{id: "pi_existing", client_secret: "pi_existing_secret"}

      expect(Edenflowers.External.StripeAPI.Mock, :retrieve_payment_intent, fn ^order ->
        {:ok, payment_intent}
      end)

      assert {:ok, ^order, "pi_existing_secret"} = Payment.setup_payment(order, nil)
    end

    test "returns an error when creating the payment intent fails" do
      order = generate(order(state: :payment))

      expect(Edenflowers.External.StripeAPI.Mock, :create_payment_intent, fn ^order ->
        {:error, :network_error}
      end)

      capture_log(fn ->
        assert {:error, :payment_intent_create_failed} = Payment.setup_payment(order, nil)
      end)
    end

    test "cancels an orphaned intent when persistence fails" do
      order = generate(order(state: :placed))
      payment_intent = %{id: "pi_orphan", client_secret: "pi_orphan_secret"}

      expect(Edenflowers.External.StripeAPI.Mock, :create_payment_intent, fn ^order ->
        {:ok, payment_intent}
      end)

      expect(Edenflowers.External.StripeAPI.Mock, :cancel_payment_intent, fn ^payment_intent ->
        {:ok, %{id: "pi_orphan", status: "canceled"}}
      end)

      capture_log(fn ->
        assert {:error, :payment_intent_persist_failed} = Payment.setup_payment(order, nil)
      end)
    end

    test "returns an error when retrieving the payment intent fails" do
      order = generate(order(state: :payment, payment_intent_id: "pi_existing"))

      expect(Edenflowers.External.StripeAPI.Mock, :retrieve_payment_intent, fn ^order ->
        {:error, :not_found}
      end)

      capture_log(fn ->
        assert {:error, :payment_intent_retrieve_failed} = Payment.setup_payment(order, nil)
      end)
    end
  end

  describe "update_payment/2" do
    test "freezes the order before updating the payment intent" do
      order = generate(order(state: :payment, payment_intent_id: "pi_update"))
      payment_intent = %{id: "pi_update", amount: 7_500}

      expect(Edenflowers.External.StripeAPI.Mock, :update_payment_intent, fn frozen_order ->
        assert frozen_order.state == :confirming_payment
        {:ok, payment_intent}
      end)

      assert {:ok, frozen_order} = Payment.update_payment(order, nil)
      assert frozen_order.state == :confirming_payment
    end

    test "returns Stripe update errors and releases the order" do
      order = generate(order(state: :payment, payment_intent_id: "pi_update"))

      expect(Edenflowers.External.StripeAPI.Mock, :update_payment_intent, fn frozen_order ->
        assert frozen_order.state == :confirming_payment
        {:error, :invalid_amount}
      end)

      assert {:error, :invalid_amount} = Payment.update_payment(order, nil)

      assert %{state: :payment, payment_intent_id: "pi_update"} =
               Edenflowers.Orders.get_order_by_id!(order.id, authorize?: false)
    end

    test "a stale concurrent request cannot release an active confirmation" do
      order = generate(order(state: :payment, payment_intent_id: "pi_update"))
      payment_intent = %{id: "pi_update", amount: 7_500}

      expect(Edenflowers.External.StripeAPI.Mock, :update_payment_intent, fn _order ->
        {:ok, payment_intent}
      end)

      assert {:ok, frozen_order} = Payment.update_payment(order, nil)
      assert {:error, _reason} = Payment.update_payment(order, nil)
      assert %{state: :confirming_payment} = Edenflowers.Orders.get_order_by_id!(frozen_order.id, authorize?: false)
    end

    test "retries with the same frozen order without touching Stripe" do
      order = generate(order(state: :confirming_payment, payment_intent_id: "pi_update"))

      assert {:ok, ^order} = Payment.update_payment(order, nil)
    end

    test "does not retry from stale state after cancellation" do
      stale_order = generate(order(state: :confirming_payment, payment_intent_id: "pi_canceled"))
      assert {:ok, %{state: :payment}} = Orders.cancel_payment_confirmation(stale_order, authorize?: false)

      assert {:error, :payment_confirmation_not_active} = Payment.update_payment(stale_order, nil)
    end
  end
end
