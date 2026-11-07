defmodule Edenflowers.Payments.PurchasePaymentRegressionTest do
  use Edenflowers.DataCase, async: true
  import Generator
  alias Edenflowers.Courses
  alias Edenflowers.Orders
  alias Edenflowers.Payments.Workers.SendCancelledEmail

  setup do
    %{admin: generate(admin_user())}
  end

  test "bank transfers and reversals remain purchase owned", %{admin: admin} do
    order = placed_order(payment_terms: :invoice, payment_intent_id: nil)
    {:ok, order} = Orders.record_payment(order, "20.00", :zervant, actor: admin)
    order = Ash.load!(order, [:payments, :amount_paid], authorize?: false)
    assert [%{invoice_id: nil, order_id: id} = payment] = order.payments
    assert id == order.id
    assert Decimal.equal?(order.amount_paid, "20.00")
    {:ok, order} = Orders.undo_payment(order, payment.id, actor: admin)
    assert Decimal.equal?(Ash.load!(order, :amount_paid, authorize?: false).amount_paid, 0)
  end

  test "unpaid cancellation charge remains a booking balance and can be paid without an invoice", %{admin: admin} do
    registration = generate(course_registration(status: :confirmed, payment_terms: :invoice, locale: "en-GB"))

    {:ok, cancelled} =
      Courses.cancel_registration(registration, %{cancellation_charge: "20", email_customer?: true}, actor: admin)

    cancelled = Ash.load!(cancelled, [:balance, :cancelled_unsettled?], authorize?: false)
    assert Decimal.equal?(cancelled.balance, "20")
    assert cancelled.cancelled_unsettled?
    [job] = all_enqueued(worker: SendCancelledEmail)
    assert :ok = perform_job(SendCancelledEmail, job.args)

    Swoosh.TestAssertions.assert_email_sent(fn email ->
      assert email.text_body =~ "There's a cancellation charge of 20,00 €. I'll be in touch about how to pay it."
      refute email.text_body =~ "invoice"
      true
    end)

    {:ok, paid} = Courses.record_registration_payment(cancelled, "20", :zervant, actor: admin)
    paid = Ash.load!(paid, [:balance, :payments, :cancelled_unsettled?], authorize?: false)
    assert Decimal.equal?(paid.balance, 0)
    refute paid.cancelled_unsettled?
    assert [%{invoice_id: nil, course_registration_id: id}] = paid.payments
    assert id == registration.id
  end
end
