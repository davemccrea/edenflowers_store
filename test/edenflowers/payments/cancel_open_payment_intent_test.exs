defmodule Edenflowers.Payments.CancelOpenPaymentIntentTest do
  use Edenflowers.DataCase, async: true

  import ExUnit.CaptureLog
  import Generator
  import Mox

  alias Edenflowers.Courses
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

  test "offline collection and late Stripe success on a manual booking retain both real payments" do
    admin = generate(admin_user())
    course = generate(course())

    booking =
      Courses.add_registration_manually!(
        %{name: "Ada", email: "ada@example.com", course_id: course.id, email_customer?: false},
        actor: admin
      )
      |> Ash.Seed.update!(%{payment_intent_id: "pi_course_double_collection"})

    expect(StripeAPI.Mock, :cancel_payment_intent, fn _intent -> {:error, :processing} end)

    capture_log(fn ->
      assert {:ok, _collected} = Courses.record_registration_payment(booking, "85.00", :cash, actor: admin)

      assert {:ok, :completed} =
               Payments.complete(%{
                 id: booking.payment_intent_id,
                 metadata: %{"course_registration_id" => booking.id},
                 amount_received: 8_500
               })
    end)

    paid = Ash.reload!(booking, authorize?: false, load: [:payments, :balance])
    assert paid.confirmed_at == booking.confirmed_at
    assert paid.status == :confirmed
    assert length(paid.payments) == 2
    assert Decimal.equal?(paid.balance, "-85.00")
    assert Ash.load!(course, :seats_booked, authorize?: false).seats_booked == 1
    refute_enqueued(worker: Edenflowers.Courses.Workers.SendConfirmationEmail)
  end

  test "a cancellation response still reporting processing retains the attached intent" do
    order = placed_order(payment_intent_id: "pi_processing_response")

    expect(StripeAPI.Mock, :cancel_payment_intent, fn %{id: id} ->
      {:ok, %{id: id, status: "processing"}}
    end)

    capture_log(fn ->
      assert {:ok, recorded} = Orders.record_payment(order, "10.00", :cash, authorize?: false)
      assert recorded.payment_intent_id == "pi_processing_response"
    end)

    assert Ash.reload!(order, authorize?: false).payment_intent_id == "pi_processing_response"
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
