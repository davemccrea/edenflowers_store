defmodule Edenflowers.Orders.Workers.ReconcileStripePaymentsTest do
  use Edenflowers.DataCase

  import ExUnit.CaptureLog
  import Generator
  import Mox

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Order
  alias Edenflowers.Orders.Workers.{ReconcileStripePayments, SendOrderConfirmationEmail}

  setup :verify_on_exit!

  setup do
    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    product_variant = generate(product_variant(product_id: product.id))
    fulfillment_option = generate(fulfillment_option(tax_rate_id: tax_rate.id))

    {:ok, %{fulfillment_fee: fulfillment_fee}} =
      Edenflowers.Fulfillment.calculate_price(fulfillment_option.id, 0)

    {:ok, user} =
      Edenflowers.Accounts.upsert_user("john.smith@example.com", "John Smith", authorize?: false)

    seed_order = fn updated_at ->
      order =
        Ash.Seed.seed!(Order, %{
          order_reference: :crypto.strong_rand_bytes(6) |> Base.encode16(),
          state: :confirming_payment,
          customer_name: "John Smith",
          customer_email: "john.smith@example.com",
          user_id: user.id,
          fulfillment_option_id: fulfillment_option.id,
          fulfillment_date: Date.utc_today(),
          fulfillment_fee: fulfillment_fee,
          payment_intent_id: "pi_test_#{System.unique_integer([:positive])}",
          updated_at: updated_at
        })

      generate(line_item(order_id: order.id, product_variant_id: product_variant.id, quantity: 1))

      Ash.get!(Order, order.id, load: [:grand_total], authorize?: false)
    end

    %{seed_order: seed_order}
  end

  defp minutes_ago(minutes), do: DateTime.add(DateTime.utc_now(), -minutes, :minute)

  defp payment_intent(order, status) do
    %{id: order.payment_intent_id, status: status, amount_received: StripeAPI.to_stripe_amount(order.grand_total)}
  end

  test "places a paid order the webhook missed, enqueues its email and logs an error", %{seed_order: seed_order} do
    order = seed_order.(minutes_ago(10))

    expect(StripeAPI.Mock, :retrieve_payment_intent, fn _order -> {:ok, payment_intent(order, "succeeded")} end)

    log = capture_log(fn -> assert :ok = perform_job(ReconcileStripePayments, %{}) end)

    assert log =~ "webhook did not arrive"
    assert %{state: :placed, payment_status: :paid} = Orders.get_order_by_id!(order.id, authorize?: false)
    assert_enqueued(worker: SendOrderConfirmationEmail, args: %{"order_id" => order.id})
  end

  test "leaves an unpaid order in checkout", %{seed_order: seed_order} do
    order = seed_order.(minutes_ago(10))

    expect(StripeAPI.Mock, :retrieve_payment_intent, fn _order ->
      {:ok, payment_intent(order, "requires_payment_method")}
    end)

    assert :ok = perform_job(ReconcileStripePayments, %{})

    assert %{state: :confirming_payment} = Orders.get_order_by_id!(order.id, authorize?: false)
    refute_enqueued(worker: SendOrderConfirmationEmail)
  end

  test "releases a canceled payment for editing", %{seed_order: seed_order} do
    order = seed_order.(minutes_ago(10))

    expect(StripeAPI.Mock, :retrieve_payment_intent, fn _order ->
      {:ok, payment_intent(order, "canceled")}
    end)

    assert :ok = perform_job(ReconcileStripePayments, %{})
    assert %{state: :payment, payment_status: :failed} = Orders.get_order_by_id!(order.id, authorize?: false)
  end

  test "skips recent confirmations but keeps reconciling old ones", %{seed_order: seed_order} do
    seed_order.(minutes_ago(1))
    old_order = seed_order.(minutes_ago(8 * 24 * 60))

    expect(StripeAPI.Mock, :retrieve_payment_intent, fn %{id: id} ->
      assert id == old_order.id
      {:ok, payment_intent(old_order, "processing")}
    end)

    assert :ok = perform_job(ReconcileStripePayments, %{})
  end

  test "cancels a payment abandoned mid-confirmation and unlocks the order", %{seed_order: seed_order} do
    order = seed_order.(minutes_ago(90))

    expect(StripeAPI.Mock, :retrieve_payment_intent, fn _order -> {:ok, payment_intent(order, "requires_action")} end)

    expect(StripeAPI.Mock, :cancel_payment_intent, fn %{id: id} ->
      assert id == order.payment_intent_id
      {:ok, %{id: id, status: "canceled"}}
    end)

    assert :ok = perform_job(ReconcileStripePayments, %{})

    assert %{state: :payment, payment_intent_id: nil} = Orders.get_order_by_id!(order.id, authorize?: false)
  end

  test "keeps an abandoned payment locked when Stripe cancellation fails", %{seed_order: seed_order} do
    order = seed_order.(minutes_ago(90))

    expect(StripeAPI.Mock, :retrieve_payment_intent, fn _order -> {:ok, payment_intent(order, "requires_action")} end)
    expect(StripeAPI.Mock, :cancel_payment_intent, fn _payment_intent -> {:error, :network_error} end)

    capture_log(fn -> assert :ok = perform_job(ReconcileStripePayments, %{}) end)

    assert %{state: :confirming_payment, payment_intent_id: payment_intent_id} =
             Orders.get_order_by_id!(order.id, authorize?: false)

    assert payment_intent_id == order.payment_intent_id
  end
end
