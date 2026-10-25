defmodule Edenflowers.Payments.ReconcilePaymentTest do
  use Edenflowers.DataCase, async: true

  import ExUnit.CaptureLog
  import Generator
  import Mox

  alias Edenflowers.Courses
  alias Edenflowers.Courses.Schedulers.ReconcilePayment, as: ScheduleCourseReconciliation

  alias Edenflowers.Courses.Workers.ReconcilePayment,
    as: ReconcileCoursePayment

  alias Edenflowers.Courses.Workers.SendConfirmationEmail,
    as: SendCourseConfirmationEmail

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Schedulers.ReconcilePayment, as: ScheduleOrderReconciliation
  alias Edenflowers.Orders.Workers.ReconcilePayment, as: ReconcileOrderPayment
  alias Edenflowers.Orders.Workers.SendReceiptEmail
  alias Edenflowers.Payments

  setup :verify_on_exit!

  defp minutes_ago(minutes), do: DateTime.add(DateTime.utc_now(), -minutes, :minute)

  defp payment_intent(order, status) do
    %{
      id: order.payment_intent_id,
      status: status,
      metadata: %{"order_id" => order.id},
      amount_received: StripeAPI.to_stripe_amount(order.grand_total)
    }
  end

  test "places a paid order the webhook missed, enqueues its email and logs an error" do
    order = order_in_payment(updated_at: minutes_ago(10))

    expect(StripeAPI.Mock, :retrieve_payment_intent, fn _order -> {:ok, payment_intent(order, "succeeded")} end)

    log =
      capture_log(fn ->
        assert {:ok, _record} =
                 perform_job(ReconcileOrderPayment, %{"primary_key" => %{"id" => order.id}})
      end)

    assert log =~ "webhook did not arrive"

    assert %{state: :placed, payment_status: :paid} =
             Orders.get_order_by_id!(order.id, authorize?: false, load: [:payment_status])

    assert_enqueued(worker: SendReceiptEmail, args: %{"primary_key" => %{"id" => order.id}})
  end

  test "confirms a paid course booking the webhook missed and logs an error" do
    registration =
      generate(
        course_registration(
          payment_intent_id: "pi_course_#{System.unique_integer([:positive])}",
          updated_at: minutes_ago(10)
        )
      )

    expect(StripeAPI.Mock, :retrieve_payment_intent, fn _registration ->
      {:ok,
       %{
         id: registration.payment_intent_id,
         status: "succeeded",
         metadata: %{"course_registration_id" => registration.id},
         amount_received: 8_500
       }}
    end)

    log =
      capture_log(fn ->
        assert {:ok, _record} =
                 perform_job(ReconcileCoursePayment, %{
                   "primary_key" => %{"id" => registration.id}
                 })
      end)

    assert log =~ "webhook did not arrive"
    assert Courses.get_registration_by_id!(registration.id, authorize?: false).status == :confirmed

    assert_enqueued(
      worker: SendCourseConfirmationEmail,
      args: %{"primary_key" => %{"id" => registration.id}}
    )
  end

  test "reconciles a confirmed booking's link payment once, even when its webhook arrives later" do
    confirmed_at = DateTime.truncate(minutes_ago(20), :second)

    registration =
      generate(
        course_registration(
          status: :confirmed,
          confirmed_at: confirmed_at,
          payment_link_token: "course_link",
          payment_intent_id: "pi_course_link",
          updated_at: minutes_ago(10)
        )
      )

    generate(
      payment(
        course_registration_id: registration.id,
        method: :stripe,
        amount: Decimal.new("30.00"),
        payment_intent_id: "pi_course_initial"
      )
    )

    intent = %{
      id: registration.payment_intent_id,
      status: "succeeded",
      metadata: %{"course_registration_id" => registration.id},
      amount_received: 5_500
    }

    assert :ok = perform_job(ScheduleCourseReconciliation, %{})
    assert_enqueued(worker: ReconcileCoursePayment, args: %{"primary_key" => %{"id" => registration.id}})

    expect(StripeAPI.Mock, :retrieve_payment_intent, fn %{id: id} ->
      assert id == registration.id
      {:ok, intent}
    end)

    log =
      capture_log(fn ->
        assert {:ok, _record} =
                 perform_job(ReconcileCoursePayment, %{"primary_key" => %{"id" => registration.id}})
      end)

    assert log =~ "webhook did not arrive"
    assert {:ok, :already_completed} = Payments.complete(intent)

    paid =
      Courses.get_registration_by_id!(registration.id,
        authorize?: false,
        load: [:payments, :settled?, :payment_link_open?]
      )

    assert paid.status == :confirmed
    assert paid.confirmed_at == confirmed_at
    assert paid.payment_intent_id == nil
    assert paid.settled?
    refute paid.payment_link_open?
    assert length(paid.payments) == 2
    assert Enum.any?(paid.payments, &(&1.payment_intent_id == intent.id and Decimal.equal?(&1.amount, "55.00")))

    assert [_one_email] =
             all_enqueued(
               worker: Edenflowers.Courses.Workers.SendPaymentReceivedEmail,
               args: %{"primary_key" => %{"id" => registration.id}}
             )

    refute_enqueued(worker: SendCourseConfirmationEmail)
  end

  test "skips cancelled bookings, bookings without an intent, fresh payments and old checkouts" do
    for opts <- [
          [status: :cancelled, updated_at: minutes_ago(10)],
          [status: :confirmed, payment_intent_id: nil, updated_at: minutes_ago(10)],
          [status: :confirmed, updated_at: minutes_ago(1)],
          [status: :confirmed, updated_at: minutes_ago(8 * 24 * 60)]
        ] do
      generate(course_registration(Keyword.put_new(opts, :payment_intent_id, "pi_skip")))
    end

    assert :ok = perform_job(ScheduleCourseReconciliation, %{})
    refute_enqueued(worker: ReconcileCoursePayment)
  end

  test "places a paid order the customer stepped back from while paying" do
    order = order_in_payment(updated_at: minutes_ago(10))

    Ecto.Adapters.SQL.query!(Edenflowers.Repo, "UPDATE orders SET state = 'delivery' WHERE id = $1", [
      Ecto.UUID.dump!(order.id)
    ])

    assert :ok = perform_job(ScheduleOrderReconciliation, %{})
    expect(StripeAPI.Mock, :retrieve_payment_intent, fn _order -> {:ok, payment_intent(order, "succeeded")} end)

    capture_log(fn ->
      assert {:ok, _record} = perform_job(ReconcileOrderPayment, %{"primary_key" => %{"id" => order.id}})
    end)

    assert_enqueued(worker: ReconcileOrderPayment, args: %{"primary_key" => %{"id" => order.id}})

    assert %{state: :placed, payment_status: :paid} =
             Orders.get_order_by_id!(order.id, authorize?: false, load: [:payment_status])
  end

  test "leaves an unpaid order in checkout" do
    order = order_in_payment(updated_at: minutes_ago(10))

    expect(StripeAPI.Mock, :retrieve_payment_intent, fn _order ->
      {:ok, payment_intent(order, "requires_payment_method")}
    end)

    assert {:ok, _record} =
             perform_job(ReconcileOrderPayment, %{"primary_key" => %{"id" => order.id}})

    # Eligibility ages out on updated_at, so reconciling must not touch it.
    assert %{state: :payment, updated_at: updated_at} = Orders.get_order_by_id!(order.id, authorize?: false)
    assert updated_at == order.updated_at
    refute_enqueued(worker: SendReceiptEmail)
  end

  test "skips orders still within the webhook grace period and abandoned checkouts" do
    order_in_payment(updated_at: minutes_ago(1))
    order_in_payment(updated_at: minutes_ago(8 * 24 * 60))

    # verify_on_exit! fails the test if Stripe is called.
    assert :ok = perform_job(ScheduleOrderReconciliation, %{})
  end
end
