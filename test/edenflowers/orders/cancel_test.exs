defmodule Edenflowers.Orders.CancelTest do
  use Edenflowers.DataCase, async: true

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
             Orders.cancel_order(order, %{refund: "68.50", held: "88.50", cancellation_reason: "I'm ill that day."},
               actor: admin
             )

    assert cancelled.fulfillment_status == :cancelled
    assert Decimal.equal?(balance(cancelled), 0)
    assert cancelled.cancellation_emailed_to == order.customer_email

    email = sent_email()
    assert email.text_body =~ "I'm ill that day."
    assert email.text_body =~ "€68.50"
    assert email.text_body =~ "If you have any questions"
    refute email.text_body =~ "didn't mean to cancel"
  end

  test "money paid in person is left to hand back, and the email says so", %{admin: admin} do
    order = placed_order(payment_intent_id: nil)
    generate(payment(order_id: order.id, amount: Decimal.new("20.00"), method: :cash))

    assert {:ok, cancelled} = Orders.cancel_order(order, %{}, actor: admin)

    assert Decimal.equal?(balance(cancelled), "-20.00")
    assert sent_email().text_body =~ "I'll pay back €20.00 the same way you paid it."
  end

  test "no address emails nobody", %{admin: admin} do
    no_address = placed_order(payment_intent_id: nil, customer_email: nil)
    {:ok, _cancelled} = Orders.cancel_order(no_address, %{}, actor: admin)

    refute_enqueued(worker: SendCancelledEmail)
  end
end
