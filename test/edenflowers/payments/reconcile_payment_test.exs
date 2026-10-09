defmodule Edenflowers.Payments.ReconcilePaymentTest do
  use Edenflowers.DataCase, async: true

  import ExUnit.CaptureLog
  import Generator
  import Mox

  alias Edenflowers.Courses

  alias Edenflowers.Courses.Workers.ReconcilePayment,
    as: ReconcileCoursePayment

  alias Edenflowers.Courses.Workers.SendConfirmationEmail,
    as: SendCourseConfirmationEmail

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Order
  alias Edenflowers.Orders.Schedulers.ReconcilePayment, as: ScheduleOrderReconciliation
  alias Edenflowers.Orders.Workers.ReconcilePayment, as: ReconcileOrderPayment
  alias Edenflowers.Orders.Workers.SendConfirmationEmail, as: SendOrderConfirmationEmail

  setup :verify_on_exit!

  setup do
    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    product_variant = generate(product_variant(product_id: product.id))
    fulfillment_option = generate(fulfillment_option(tax_rate_id: tax_rate.id))

    %{fulfillment_fee: fulfillment_fee} = Edenflowers.Fulfillment.Fee.calculate(fulfillment_option, 0)

    {:ok, user} =
      Edenflowers.Accounts.upsert_user("john.smith@example.com", "John Smith", authorize?: false)

    seed_order = fn updated_at ->
      order =
        Ash.Seed.seed!(Order, %{
          order_reference: :crypto.strong_rand_bytes(6) |> Base.encode16(),
          state: :payment,
          customer_name: "John Smith",
          customer_email: "john.smith@example.com",
          user_id: user.id,
          fulfillment_option_id: fulfillment_option.id,
          fulfillment_date: Date.utc_today(),
          quoted_fulfillment_fee: fulfillment_fee,
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
    %{
      id: order.payment_intent_id,
      status: status,
      metadata: %{"order_id" => order.id},
      amount_received: StripeAPI.to_stripe_amount(order.grand_total)
    }
  end

  test "places a paid order the webhook missed, enqueues its email and logs an error", %{seed_order: seed_order} do
    order = seed_order.(minutes_ago(10))

    expect(StripeAPI.Mock, :retrieve_payment_intent, fn _order -> {:ok, payment_intent(order, "succeeded")} end)

    log =
      capture_log(fn ->
        assert {:ok, _record} =
                 perform_job(ReconcileOrderPayment, %{"primary_key" => %{"id" => order.id}})
      end)

    assert log =~ "webhook did not arrive"

    assert %{state: :placed, payment_status: :paid} =
             Orders.get_order_by_id!(order.id, authorize?: false, load: [:payment_status])

    assert_enqueued(worker: SendOrderConfirmationEmail, args: %{"primary_key" => %{"id" => order.id}})
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

  test "places a paid order the customer stepped back from while paying", %{seed_order: seed_order} do
    order = seed_order.(minutes_ago(10))

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

  test "leaves an unpaid order in checkout", %{seed_order: seed_order} do
    order = seed_order.(minutes_ago(10))

    expect(StripeAPI.Mock, :retrieve_payment_intent, fn _order ->
      {:ok, payment_intent(order, "requires_payment_method")}
    end)

    assert {:ok, _record} =
             perform_job(ReconcileOrderPayment, %{"primary_key" => %{"id" => order.id}})

    # Eligibility ages out on updated_at, so reconciling must not touch it.
    assert %{state: :payment, updated_at: updated_at} = Orders.get_order_by_id!(order.id, authorize?: false)
    assert updated_at == order.updated_at
    refute_enqueued(worker: SendOrderConfirmationEmail)
  end

  test "skips orders still within the webhook grace period and abandoned checkouts", %{seed_order: seed_order} do
    seed_order.(minutes_ago(1))
    seed_order.(minutes_ago(8 * 24 * 60))

    # verify_on_exit! fails the test if Stripe is called.
    assert :ok = perform_job(ScheduleOrderReconciliation, %{})
  end
end
