defmodule Edenflowers.Orders.Order.Changes.SendPaymentFailedEmailTest do
  use Edenflowers.DataCase, async: true

  import Generator
  import Swoosh.TestAssertions

  alias Edenflowers.Orders.Workers.SendPaymentFailedEmail

  for {scenario, attrs} <- [
        {"paid", [paid: true]},
        {"refunded", [refunded: true]},
        {"cancelled with money still to collect", [fulfillment_status: :cancelled, kept_amount: "10.00"]}
      ] do
    test "a queued payment failure is skipped once the order is #{scenario}" do
      order = placed_order(unquote(Macro.escape(attrs)))

      assert {:cancel, :trigger_no_longer_applies} =
               perform_job(SendPaymentFailedEmail, %{"primary_key" => %{"id" => order.id}})

      assert_no_email_sent()
    end
  end

  test "the sender rechecks payment even when called with an unpaid copy" do
    order = placed_order()
    generate(payment(order_id: order.id, amount: order.grand_total))

    assert {:ok, _order} = Ash.update(order, %{}, action: :send_payment_failed_email, authorize?: false)
    assert_no_email_sent()
  end

  test "an unpaid placed order still receives its payment link" do
    order = placed_order(origin: :subscription, payment_link_token: "payment-failed-test")

    assert {:ok, _order} = perform_job(SendPaymentFailedEmail, %{"primary_key" => %{"id" => order.id}})

    assert_email_sent(fn email ->
      assert email.to == [{"", order.customer_email}]
      assert email.text_body =~ EdenflowersWeb.PaymentLink.url_for(order)
      assert email.text_body =~ "didn't go through, but your order will still go ahead as planned."

      assert email.text_body =~
               "Please pay #{Edenflowers.Format.currency(order.grand_total, order.locale)} using the link below:"

      assert email.text_body =~ "Future orders are on hold until this one is paid."
      assert email.text_body =~ "Please also update your saved card in your account:"
    end)
  end
end
