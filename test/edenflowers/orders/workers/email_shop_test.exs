defmodule Edenflowers.Orders.Workers.EmailShopTest do
  # Not async: one test unsets the shop address, which is application env.
  use Edenflowers.DataCase, async: false
  import Swoosh.TestAssertions
  import Generator

  alias Edenflowers.Orders
  alias Edenflowers.Orders.Workers.EmailShop

  test "placing an order at checkout queues the email" do
    order = generate(order(state: :payment, payment_intent_id: "pi_test"))

    Orders.finalize_checkout!(order.id, order.payment_intent_id, %{amount_paid: "0.00"}, authorize?: false)

    assert_enqueued worker: EmailShop, args: %{"order_id" => order.id}
  end

  test "nothing is queued without a shop address, as on staging" do
    Application.delete_env(:edenflowers, :shop_notice_email)
    on_exit(fn -> Application.put_env(:edenflowers, :shop_notice_email, "shop@example.com") end)
    order = generate(order(state: :payment, payment_intent_id: "pi_test"))

    Orders.finalize_checkout!(order.id, order.payment_intent_id, %{amount_paid: "0.00"}, authorize?: false)

    refute_enqueued worker: EmailShop
  end

  test "tells the shop's inbox about a same-day order, linking to it in the admin" do
    order = placed_order(fulfillment_date: Edenflowers.ShopTime.today(), order_reference: "1042")

    assert :ok = perform_job(EmailShop, %{"notice" => "new", "order_id" => order.id})

    assert_email_sent(fn email ->
      assert email.to == [{"", "shop@example.com"}]
      assert email.bcc == []
      assert email.subject == "Avhämtning för idag 1042"
      refute email.text_body =~ "kl."
      assert email.text_body =~ "/admin/orders/#{order.id}"
    end)
  end

  test "says when an order with a window is due" do
    order =
      placed_order(
        fulfillment_date: ~D[2026-06-12],
        fulfillment_time_start: ~T[12:00:00],
        fulfillment_time_end: ~T[16:00:00]
      )

    assert :ok = perform_job(EmailShop, %{"notice" => "new", "order_id" => order.id})

    assert_email_sent(fn email ->
      assert email.text_body =~ ~r/^fredag 12.6.2026 kl. 12.00–16.00\n\nÖppna i adminpanelen:/
    end)
  end
end
