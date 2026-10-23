defmodule Edenflowers.Orders.Changes.SendFulfillmentEmailTest do
  use Edenflowers.DataCase, async: true

  import Generator
  import Swoosh.TestAssertions

  alias Edenflowers.Orders
  alias Edenflowers.Orders.Workers.SendFulfillmentEmail

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

  defp stub_delivery_photo do
    Req.Test.stub(Edenflowers.Orders.Changes.SendFulfillmentEmail, fn conn ->
      assert conn.host == "imgproxy.test"
      assert conn.request_path =~ "rs:fit:1600:1600"
      assert conn.request_path =~ "q:80"
      Plug.Conn.send_resp(conn, 200, "small jpeg")
    end)
  end

  describe "marking an order fulfilled" do
    test "queues the fulfillment email for a delivery order" do
      order = fulfillable_order([])

      {:ok, _order} = Orders.mark_order_fulfilled(order, actor: admin())

      assert_enqueued(worker: SendFulfillmentEmail, args: %{"primary_key" => %{"id" => order.id}})
    end

    test "sends nothing for a collected order, as the customer was there" do
      order = fulfillable_order(fulfillment_method: :pickup, origin: :custom)

      {:ok, _order} = Orders.mark_order_fulfilled(order, actor: admin())

      refute_enqueued(worker: SendFulfillmentEmail)
      assert_no_email_sent()
    end

    test "sends nothing to a phone-only customer" do
      order = fulfillable_order(customer_email: nil, customer_phone_number: "+358401234567")

      {:ok, _order} = Orders.mark_order_fulfilled(order, actor: admin())

      refute_enqueued(worker: SendFulfillmentEmail)
      assert %{failure: 0} = Oban.drain_queue(queue: :default)
      assert_no_email_sent()
    end

    test "sends nothing when Jennie chose not to email the customer" do
      order = fulfillable_order([])

      {:ok, order} = Orders.mark_order_fulfilled(order, %{email_customer?: false}, actor: admin())

      assert order.fulfillment_status == :fulfilled
      refute_enqueued(worker: SendFulfillmentEmail)
      assert %{failure: 0} = Oban.drain_queue(queue: :default)
      assert_no_email_sent()
    end

    test "queues nothing when the order is already fulfilled" do
      order = fulfillable_order(fulfillment_status: :fulfilled)

      assert {:error, _} = Orders.mark_order_fulfilled(order, actor: admin())

      refute_enqueued(worker: SendFulfillmentEmail)
    end

    test "the domain disables photo emailing when confirmation emailing is declined" do
      order = fulfillable_order([])

      assert {:ok, order} =
               Orders.mark_order_fulfilled(
                 order,
                 %{
                   email_customer?: false,
                   email_delivery_photo: true,
                   delivery_photo_slug: "local:///uploads/door.jpg"
                 },
                 actor: admin()
               )

      assert order.fulfillment_status == :fulfilled
      refute order.email_delivery_photo
      assert order.delivery_photo_slug == "local:///uploads/door.jpg"
      refute_enqueued(worker: SendFulfillmentEmail)
    end

    test "the domain rejects emailing a delivery photo without a photo" do
      order = fulfillable_order([])

      assert {:error, _} = Orders.mark_order_fulfilled(order, %{email_delivery_photo: true}, actor: admin())
      assert Orders.get_order_by_id!(order.id, authorize?: false).fulfillment_status == :pending
      refute_enqueued(worker: SendFulfillmentEmail)
    end
  end

  describe "the trigger" do
    test "tells the customer their gift reached the recipient" do
      order = fulfillable_order(gift: true, recipient_name: "Grace Hopper", fulfillment_status: :fulfilled)

      assert {:ok, _} = perform_job(SendFulfillmentEmail, %{"primary_key" => %{"id" => order.id}})

      assert_email_sent(fn email ->
        assert email.to == [{"", "ada@example.com"}]
        assert email.bcc == [{"Jennie", "info+copy@edenflowers.fi"}]
        assert email.subject == "Your Eden Flowers order 1400 has been delivered"
        assert email.text_body =~ "Hi Ada,"
        assert email.text_body =~ "Your order for Grace has been delivered."
      end)

      reloaded = Orders.get_order_by_id!(order.id, authorize?: false)
      assert reloaded.fulfillment_emailed_at != nil
    end

    test "leaves out the recipient when the order isn't a gift" do
      order =
        fulfillable_order(
          gift: false,
          customer_name: "Sara Smith",
          recipient_name: "Sara Smith",
          fulfillment_status: :fulfilled
        )

      assert {:ok, _} = perform_job(SendFulfillmentEmail, %{"primary_key" => %{"id" => order.id}})

      assert_email_sent(fn email ->
        assert email.text_body =~ "Hi Sara,"
        refute email.text_body =~ "Your order for Sara"
        assert email.text_body =~ "Your order has been delivered."
      end)
    end

    test "writes in the order's language" do
      order = fulfillable_order(locale: "sv-FI", fulfillment_status: :fulfilled)

      assert {:ok, _} = perform_job(SendFulfillmentEmail, %{"primary_key" => %{"id" => order.id}})

      assert_email_sent(fn email ->
        assert email.subject == "Din Eden Flowers-beställning 1400 har levererats"
        assert email.text_body =~ "Hej Ada,"
        assert email.text_body =~ "Din beställning har levererats."
      end)
    end

    @tag capture_log: true
    test "a missing opted-in photo does not fall back to a plain confirmation" do
      order = fulfillable_order(fulfillment_status: :fulfilled, email_delivery_photo: true)

      assert_raise Ash.Error.Invalid, ~r/Delivery photo is missing/, fn ->
        perform_job(SendFulfillmentEmail, %{"primary_key" => %{"id" => order.id}})
      end

      assert_no_email_sent()
      assert Orders.get_order_by_id!(order.id, authorize?: false).fulfillment_emailed_at == nil
    end

    test "sends the photo of where the order was left instead, shrunk by imgproxy" do
      stub_delivery_photo()

      order =
        fulfillable_order(
          gift: false,
          recipient_name: "Ada Lovelace",
          fulfillment_status: :fulfilled,
          delivery_photo_slug: "local:///uploads/door.jpg",
          email_delivery_photo: true
        )

      assert {:ok, _} = perform_job(SendFulfillmentEmail, %{"primary_key" => %{"id" => order.id}})

      assert_email_sent(fn email ->
        assert email.subject == "Your Eden Flowers order 1400 has been delivered"
        assert email.text_body =~ "Nobody was home"

        assert email.text_body =~
                 "Nobody was home when I delivered your order. The attached photo shows where I left it."

        assert email.text_body =~ "If anything isn't as it should be, just reply and I'll take care of it."
        refute email.text_body =~ "can't find them"
        assert [%{data: "small jpeg", content_type: "image/jpeg"}] = email.attachments
      end)
    end

    test "names the recipient when a gift was left at the door" do
      stub_delivery_photo()

      order =
        fulfillable_order(
          gift: true,
          recipient_name: "Grace Hopper",
          fulfillment_status: :fulfilled,
          delivery_photo_slug: "local:///uploads/door.jpg",
          email_delivery_photo: true
        )

      assert {:ok, _} = perform_job(SendFulfillmentEmail, %{"primary_key" => %{"id" => order.id}})

      assert_email_sent(fn email ->
        assert email.text_body =~ "delivered your order for Grace"
      end)
    end

    test "sends the usual email when Jennie chose not to send the photo" do
      order =
        fulfillable_order(
          fulfillment_status: :fulfilled,
          delivery_photo_slug: "local:///uploads/door.jpg",
          email_delivery_photo: false
        )

      assert {:ok, _} = perform_job(SendFulfillmentEmail, %{"primary_key" => %{"id" => order.id}})

      assert_email_sent(fn email ->
        assert email.text_body =~ "Your order has been delivered."
        assert email.attachments == []
      end)
    end

    test "delivery confirmation uses the customer's locale, not the worker's" do
      for {locale, reference, subject, greeting, body} <- [
            {"sv-FI", "1400", "Din Eden Flowers-beställning 1400 har levererats", "Hej Ada,",
             "Din beställning har levererats."},
            {"fi", "1401", "Eden Flowers -tilauksesi 1401 on toimitettu", "Hei Ada,", "Tilauksesi on toimitettu."}
          ] do
        order =
          fulfillable_order(
            gift: false,
            fulfillment_status: :fulfilled,
            locale: locale,
            order_reference: reference
          )

        assert {:ok, _} = perform_job(SendFulfillmentEmail, %{"primary_key" => %{"id" => order.id}})

        assert_email_sent(fn email ->
          assert email.subject == subject
          assert email.text_body =~ greeting
          assert email.text_body =~ body
        end)
      end
    end

    test "a successful send records the recipient and clears a recorded failure" do
      order = fulfillable_order(fulfillment_status: :fulfilled, fulfillment_email_failed_at: DateTime.utc_now())

      assert {:ok, _} = perform_job(SendFulfillmentEmail, %{"primary_key" => %{"id" => order.id}})

      reloaded = Orders.get_order_by_id!(order.id, authorize?: false)
      assert reloaded.fulfillment_emailed_to == "ada@example.com"
      assert reloaded.fulfillment_email_failed_at == nil
    end

    @tag capture_log: true
    test "the last failed attempt records the failure in the order log" do
      Req.Test.stub(Edenflowers.Orders.Changes.SendFulfillmentEmail, fn conn ->
        Plug.Conn.send_resp(conn, 503, "unavailable")
      end)

      order =
        fulfillable_order(
          fulfillment_status: :fulfilled,
          delivery_photo_slug: "local:///uploads/door.jpg",
          email_delivery_photo: true
        )

      args = %{"primary_key" => %{"id" => order.id}}

      assert_raise Ash.Error.Invalid, fn -> perform_job(SendFulfillmentEmail, args, attempt: 1, max_attempts: 3) end
      refute Orders.get_order_by_id!(order.id, authorize?: false).fulfillment_email_failed_at

      perform_job(SendFulfillmentEmail, args, attempt: 3, max_attempts: 3)

      reloaded = Orders.get_order_by_id!(order.id, authorize?: false)
      assert reloaded.fulfillment_email_failed_at
      assert reloaded.fulfillment_emailed_at == nil
      assert_no_email_sent()

      versions = Ash.load!(order, :paper_trail_versions, authorize?: false).paper_trail_versions
      assert Enum.any?(versions, &(&1.version_action_name == :record_fulfillment_email_failure))
    end

    test "has no scheduler to send one nobody queued" do
      refute Code.ensure_loaded?(Edenflowers.Orders.Schedulers.SendFulfillmentEmail)
    end
  end

  describe "emailing the confirmation from the admin" do
    test "queues it after Jennie unticked it, and again after it was sent" do
      order = fulfillable_order([])
      actor = admin()
      {:ok, order} = Orders.mark_order_fulfilled(order, %{email_customer?: false}, actor: actor)
      refute_enqueued(worker: SendFulfillmentEmail)

      assert {:ok, _} = Orders.email_fulfillment_confirmation(order, actor: actor)
      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :default)
      assert_email_sent()

      assert {:ok, _} = Orders.email_fulfillment_confirmation(order, actor: actor)
      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :default)
      assert_email_sent()
    end

    test "needs a fulfilled delivery with an email, and an admin" do
      assert {:error, _} =
               Orders.email_fulfillment_confirmation(fulfillable_order(order_reference: "1401"), actor: admin())

      collected =
        fulfillable_order(fulfillment_method: :pickup, fulfillment_status: :fulfilled, order_reference: "1403")

      assert {:error, _} = Orders.email_fulfillment_confirmation(collected, actor: admin())

      no_email =
        fulfillable_order(
          fulfillment_status: :fulfilled,
          order_reference: "1402",
          customer_email: nil,
          customer_phone_number: "+358401234567"
        )

      assert {:error, _} = Orders.email_fulfillment_confirmation(no_email, actor: admin())

      fulfilled = fulfillable_order(fulfillment_status: :fulfilled)

      assert {:error, _} =
               Orders.email_fulfillment_confirmation(fulfilled, actor: generate(admin_user(admin: false)))

      refute_enqueued(worker: SendFulfillmentEmail)
    end
  end
end
