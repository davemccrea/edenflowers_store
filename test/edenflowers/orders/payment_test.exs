defmodule Edenflowers.Orders.PaymentTest do
  use Edenflowers.DataCase, async: true

  import Generator
  import Mox

  import ExUnit.CaptureLog

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

  describe "update_payment/1" do
    test "updates the payment intent through the Stripe API" do
      order = generate(order(state: :payment, payment_intent_id: "pi_update"))
      payment_intent = %{id: "pi_update", amount: 7_500}

      expect(Edenflowers.External.StripeAPI.Mock, :update_payment_intent, fn ^order ->
        {:ok, payment_intent}
      end)

      assert {:ok, ^payment_intent} = Payment.update_payment(order)
    end

    test "returns Stripe update errors" do
      order = generate(order(state: :payment, payment_intent_id: "pi_update"))

      expect(Edenflowers.External.StripeAPI.Mock, :update_payment_intent, fn ^order ->
        {:error, :invalid_amount}
      end)

      assert {:error, :invalid_amount} = Payment.update_payment(order)
    end
  end
end
