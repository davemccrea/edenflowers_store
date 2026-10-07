defmodule Edenflowers.Orders.Changes.SendDeliveredEmailTest do
  use Edenflowers.DataCase, async: true

  import Generator
  import Swoosh.TestAssertions

  alias Edenflowers.Orders
  alias Edenflowers.Orders.Workers.SendDeliveredEmail

  defp fulfillable_order(overrides) do
    attrs =
      Keyword.merge(
        [
          state: :placed,
          order_reference: "1400",
          customer_name: "Ada Lovelace",
          customer_email: "ada@example.com",
          fulfillment_method: :delivery,
          fulfillment_date: ~D[2026-06-10],
          fulfillment_status: :pending,
          locale: "en-GB"
        ],
        overrides
      )

    generate(order(attrs))
  end

  defp admin, do: generate(admin_user())

  describe "marking an order fulfilled" do
    test "queues the delivered email for a delivery order" do
      order = fulfillable_order([])

      {:ok, _order} = Orders.mark_order_fulfilled(order, actor: admin())

      assert_enqueued(worker: SendDeliveredEmail, args: %{"primary_key" => %{"id" => order.id}})
    end

    test "sends nothing for a pickup order" do
      order = fulfillable_order(fulfillment_method: :pickup)

      {:ok, _order} = Orders.mark_order_fulfilled(order, actor: admin())
      Oban.drain_queue(queue: :default)

      assert_no_email_sent()
    end

    test "sends nothing to a phone-only customer" do
      order = fulfillable_order(customer_email: nil, customer_phone_number: "+358401234567")

      {:ok, _order} = Orders.mark_order_fulfilled(order, actor: admin())

      assert %{failure: 0} = Oban.drain_queue(queue: :default)
      assert_no_email_sent()
    end

    test "queues nothing when the order is already fulfilled" do
      order = fulfillable_order(fulfillment_status: :fulfilled)

      assert {:error, _} = Orders.mark_order_fulfilled(order, actor: admin())

      refute_enqueued(worker: SendDeliveredEmail)
    end
  end

  describe "the trigger" do
    test "tells the customer their gift reached the recipient" do
      order = fulfillable_order(gift: true, recipient_name: "Grace Hopper", fulfillment_status: :fulfilled)

      assert {:ok, _} = perform_job(SendDeliveredEmail, %{"primary_key" => %{"id" => order.id}})

      assert_email_sent(fn email ->
        assert email.to == [{"", "ada@example.com"}]
        assert email.subject == "Your Eden Flowers order 1400 has been delivered"
        assert email.text_body =~ "Hi Ada,"
        assert email.text_body =~ "Your flowers for Grace have been delivered."
      end)

      reloaded = Orders.get_order_by_id!(order.id, authorize?: false)
      assert reloaded.delivered_emailed_at != nil
    end

    test "leaves out the recipient when the order isn't a gift" do
      order = fulfillable_order(fulfillment_status: :fulfilled)

      assert {:ok, _} = perform_job(SendDeliveredEmail, %{"primary_key" => %{"id" => order.id}})

      assert_email_sent(fn email ->
        assert email.text_body =~ "Your flowers have been delivered."
      end)
    end

    test "writes in the order's language" do
      order = fulfillable_order(locale: "sv-FI", fulfillment_status: :fulfilled)

      assert {:ok, _} = perform_job(SendDeliveredEmail, %{"primary_key" => %{"id" => order.id}})

      assert_email_sent(fn email ->
        assert email.subject == "Din Eden Flowers-beställning 1400 har levererats"
        assert email.text_body =~ "Hej Ada,"
      end)
    end

    test "skips pickup orders" do
      order = fulfillable_order(fulfillment_method: :pickup, fulfillment_status: :fulfilled)

      perform_job(SendDeliveredEmail, %{"primary_key" => %{"id" => order.id}})

      assert_no_email_sent()
    end

    test "doesn't send twice" do
      order = fulfillable_order(fulfillment_status: :fulfilled)

      assert {:ok, _} = perform_job(SendDeliveredEmail, %{"primary_key" => %{"id" => order.id}})
      assert_email_sent()

      perform_job(SendDeliveredEmail, %{"primary_key" => %{"id" => order.id}})
      assert_no_email_sent()
    end
  end
end
