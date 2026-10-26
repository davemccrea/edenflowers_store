defmodule Edenflowers.Payments.CancelOpenPaymentIntentTest do
  use Edenflowers.DataCase, async: true

  import ExUnit.CaptureLog
  import Generator
  import Mox

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders
  alias Edenflowers.Payments

  setup :verify_on_exit!

  test "failed cancellation retains a recoverable intent while recording offline money and a later Stripe success" do
    order = placed_order(payment_intent_id: "pi_processing")
    expect(StripeAPI.Mock, :cancel_payment_intent, fn %{id: "pi_processing"} -> {:error, :processing} end)

    capture_log(fn ->
      assert {:ok, recorded} = Orders.record_payment(order, "88.50", :cash, authorize?: false)
      assert recorded.payment_intent_id == "pi_processing"
    end)

    intent = %{id: "pi_processing", metadata: %{"order_id" => order.id}, amount_received: 8_850}

    capture_log(fn -> assert {:ok, :completed} = Payments.complete(intent) end)
    assert {:ok, :already_completed} = Payments.complete(intent)

    paid = Orders.get_order_by_id!(order.id, authorize?: false, load: [:payments, :balance, :to_refund?])
    assert length(paid.payments) == 2
    assert Enum.sort(Enum.map(paid.payments, & &1.method)) == [:cash, :stripe]
    assert Decimal.equal?(paid.balance, "-88.50")
    assert paid.to_refund?
    assert is_nil(paid.payment_intent_id)
  end

  test "an old cancellation cannot clear a replacement intent attached during the Stripe call" do
    order = placed_order(payment_intent_id: "pi_old")

    expect(StripeAPI.Mock, :cancel_payment_intent, fn %{id: "pi_old"} ->
      Ash.Seed.update!(order, %{payment_intent_id: "pi_replacement"})
      {:ok, %{id: "pi_old", status: "canceled"}}
    end)

    assert {:ok, _recorded} = Orders.record_payment(order, "10.00", :cash, authorize?: false)
    assert Orders.get_order_by_id!(order.id, authorize?: false).payment_intent_id == "pi_replacement"
  end

  test "a cancelled occurrence's late payment does not restart its held subscription" do
    subscription = generate(subscription(state: :payment_failed))

    order =
      placed_order(
        origin: :subscription,
        subscription_id: subscription.id,
        fulfillment_status: :cancelled,
        payment_intent_id: "pi_cancelled_occurrence"
      )

    capture_log(fn ->
      assert {:ok, :completed} =
               Payments.complete(%{
                 id: "pi_cancelled_occurrence",
                 metadata: %{"order_id" => order.id},
                 amount_received: 8_850
               })
    end)

    assert Ash.reload!(subscription, authorize?: false).state == :payment_failed
    assert Ash.reload!(order, authorize?: false).fulfillment_status == :cancelled
  end

  test "cancelling a booking preserves a processing intent for late money without rebooking" do
    booking = generate(course_registration(status: :confirmed, payment_intent_id: "pi_booking_processing"))

    expect(StripeAPI.Mock, :cancel_payment_intent, fn %{id: "pi_booking_processing"} -> {:error, :processing} end)

    capture_log(fn ->
      assert {:ok, cancelled} =
               booking
               |> Ash.Changeset.for_update(:cancel, %{email_customer?: false}, authorize?: false)
               |> Ash.update()

      assert cancelled.status == :cancelled
      assert cancelled.payment_intent_id == "pi_booking_processing"
    end)

    capture_log(fn ->
      assert {:ok, :completed} =
               Payments.complete(%{
                 id: "pi_booking_processing",
                 metadata: %{"course_registration_id" => booking.id},
                 amount_received: 8_500
               })
    end)

    cancelled = Ash.get!(booking.__struct__, booking.id, authorize?: false, load: [:balance, :payments])
    assert cancelled.status == :cancelled
    assert is_nil(cancelled.confirmed_at)
    assert Decimal.equal?(cancelled.balance, "-85.00")
    assert length(cancelled.payments) == 1
    refute_enqueued(worker: Edenflowers.Courses.Workers.SendConfirmationEmail)
  end
end
