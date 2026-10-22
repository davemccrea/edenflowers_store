defmodule Edenflowers.Orders.CancelTest do
  use Edenflowers.DataCase, async: true

  import ExUnit.CaptureLog
  import Generator
  import Swoosh.TestAssertions

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders
  alias Edenflowers.Payments.Workers.SendCancelledEmail

  setup do
    %{admin: generate(admin_user())}
  end

  defp order_paid_by_card(opts \\ []) do
    order = placed_order(Keyword.merge([payment_intent_id: nil], opts))
    generate(payment(order_id: order.id, amount: order.grand_total, payment_intent_id: "pi_#{order.id}"))
    order
  end

  defp expect_refund(order, cents) do
    pi = "pi_#{order.id}"

    StripeAPI.Mock
    |> Mox.stub(:list_refunds, fn ^pi -> {:ok, []} end)
    |> Mox.expect(:create_refund, fn ^pi, ^cents, _key, _metadata ->
      {:ok, %{id: "re_#{order.id}", payment_intent: pi, amount: cents, status: "succeeded"}}
    end)
  end

  defp balance(order), do: Ash.load!(order, :balance, authorize?: false, reuse_values?: false).balance

  defp sent_email do
    [job] = all_enqueued(worker: SendCancelledEmail)
    assert :ok = perform_job(SendCancelledEmail, job.args)
    assert_email_sent(fn email -> send(self(), {:email, email}) end)
    assert_received {:email, email}
    email
  end

  test "refunds all but what Jennie keeps, and emails the reason", %{admin: admin} do
    order = order_paid_by_card()
    expect_refund(order, 6850)

    assert {:ok, cancelled} =
             Orders.cancel_order(order, %{kept_amount: "20.00", cancellation_reason: "I'm ill that day."}, actor: admin)

    assert cancelled.fulfillment_status == :cancelled
    assert Decimal.equal?(balance(cancelled), 0)
    assert cancelled.cancellation_emailed_to == order.customer_email

    email = sent_email()
    assert email.text_body =~ "I'm ill that day."
    assert email.text_body =~ "€68.50"
    assert email.text_body =~ "If you have any questions"
    refute email.text_body =~ "didn't mean to cancel"
  end

  test "a refund Stripe refuses leaves the order placed and emails nothing", %{admin: admin} do
    order = order_paid_by_card()

    StripeAPI.Mock
    |> Mox.stub(:list_refunds, fn _pi -> {:ok, []} end)
    |> Mox.expect(:create_refund, fn _pi, _cents, _key, _metadata -> {:error, :charge_disputed} end)

    capture_log(fn ->
      assert {:error, error} = Orders.cancel_order(order, %{}, actor: admin)
      assert Exception.message(error) =~ "Stripe refused the refund"
    end)

    assert Orders.get_order_by_id!(order.id, authorize?: false).fulfillment_status == :pending
    refute_enqueued(worker: SendCancelledEmail)
  end

  test "a retry after the refund went through refunds nothing twice", %{admin: admin} do
    order = order_paid_by_card()

    generate(
      payment(
        order_id: order.id,
        amount: Decimal.new("-68.50"),
        method: :stripe,
        stripe_refund_id: "re_first"
      )
    )

    Mox.expect(StripeAPI.Mock, :create_refund, 0, fn _pi, _cents, _key, _metadata -> flunk("refunded twice") end)

    assert {:ok, cancelled} = Orders.cancel_order(order, %{kept_amount: "20.00"}, actor: admin)
    assert Decimal.equal?(balance(cancelled), 0)
  end

  test "money paid in person is left to hand back, and the email says so", %{admin: admin} do
    order = placed_order(payment_intent_id: nil)
    generate(payment(order_id: order.id, amount: Decimal.new("20.00"), method: :cash))

    assert {:ok, cancelled} = Orders.cancel_order(order, %{}, actor: admin)

    assert Decimal.equal?(balance(cancelled), "-20.00")
    assert sent_email().text_body =~ "I'll return the €20.00 you paid me directly."
  end

  test "unticking the email, or no address, emails nobody", %{admin: admin} do
    order = placed_order(payment_intent_id: nil)
    {:ok, cancelled} = Orders.cancel_order(order, %{email_customer?: false}, actor: admin)
    assert cancelled.cancellation_emailed_to == nil

    no_address = placed_order(payment_intent_id: nil, customer_email: nil)
    {:ok, _cancelled} = Orders.cancel_order(no_address, %{}, actor: admin)

    refute_enqueued(worker: SendCancelledEmail)
  end

  test "keeping more than was paid is refused", %{admin: admin} do
    order = placed_order(payment_intent_id: nil)
    generate(payment(order_id: order.id, amount: Decimal.new("20.00"), method: :cash))

    assert {:error, error} = Orders.cancel_order(order, %{kept_amount: "20.01"}, actor: admin)
    assert Exception.message(error) =~ "more than was paid"
  end
end
