defmodule Edenflowers.CheckoutTest do
  use Edenflowers.DataCase, async: true

  import Generator
  import Mox

  alias Edenflowers.Checkout

  setup :verify_on_exit!

  describe "setup_payment/2" do
    test "creates and persists a payment intent when order has none" do
      order = generate(order(state: :payment, grand_total: Decimal.new("50.00")))
      payment_intent = %{id: "pi_new_123", client_secret: "pi_new_secret"}

      expect(Edenflowers.StripeAPI.Mock, :create_payment_intent, fn ^order ->
        {:ok, payment_intent}
      end)

      assert {:ok, updated_order, "pi_new_secret"} = Checkout.setup_payment(order, nil)
      assert updated_order.payment_intent_id == "pi_new_123"
    end

    test "retrieves an existing payment intent when order already has one" do
      order =
        generate(
          order(
            state: :payment,
            grand_total: Decimal.new("50.00"),
            payment_intent_id: "pi_existing_456"
          )
        )

      payment_intent = %{id: "pi_existing_456", client_secret: "pi_existing_secret"}

      expect(Edenflowers.StripeAPI.Mock, :retrieve_payment_intent, fn ^order ->
        {:ok, payment_intent}
      end)

      assert {:ok, ^order, "pi_existing_secret"} = Checkout.setup_payment(order, nil)
    end

    test "returns error when Stripe create fails" do
      order = generate(order(state: :payment, grand_total: Decimal.new("50.00")))

      expect(Edenflowers.StripeAPI.Mock, :create_payment_intent, fn ^order ->
        {:error, %{message: "network timeout"}}
      end)

      assert {:error, :payment_intent_create_failed} = Checkout.setup_payment(order, nil)
    end

    test "returns error and cancels orphan intent when persist fails" do
      # A placed order rejects add_payment_intent_id, simulating a persist failure.
      order = generate(order(state: :placed, grand_total: Decimal.new("50.00")))
      payment_intent = %{id: "pi_orphan_789", client_secret: "pi_orphan_secret"}

      expect(Edenflowers.StripeAPI.Mock, :create_payment_intent, fn ^order ->
        {:ok, payment_intent}
      end)

      expect(Edenflowers.StripeAPI.Mock, :cancel_payment_intent, fn ^payment_intent ->
        {:ok, %{id: "pi_orphan_789", status: "canceled"}}
      end)

      assert {:error, :payment_intent_persist_failed} =
               Checkout.setup_payment(order, nil)
    end

    test "returns error when Stripe retrieve fails" do
      order =
        generate(
          order(
            state: :payment,
            grand_total: Decimal.new("50.00"),
            payment_intent_id: "pi_existing_456"
          )
        )

      expect(Edenflowers.StripeAPI.Mock, :retrieve_payment_intent, fn ^order ->
        {:error, %{message: "not found"}}
      end)

      assert {:error, :payment_intent_retrieve_failed} = Checkout.setup_payment(order, nil)
    end
  end

  describe "update_payment/1" do
    test "delegates to the Stripe API port" do
      order = generate(order(payment_intent_id: "pi_update_001", grand_total: Decimal.new("75.00")))
      updated_intent = %{id: "pi_update_001", amount: 7500}

      expect(Edenflowers.StripeAPI.Mock, :update_payment_intent, fn ^order ->
        {:ok, updated_intent}
      end)

      assert {:ok, ^updated_intent} = Checkout.update_payment(order)
    end

    test "returns error when Stripe update fails" do
      order = generate(order(payment_intent_id: "pi_update_002", grand_total: Decimal.new("75.00")))

      expect(Edenflowers.StripeAPI.Mock, :update_payment_intent, fn ^order ->
        {:error, %{message: "invalid amount"}}
      end)

      assert {:error, %{message: "invalid amount"}} = Checkout.update_payment(order)
    end
  end
end
