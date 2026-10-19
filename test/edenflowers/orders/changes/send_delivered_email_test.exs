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

  describe "confirmation email status and retry" do
    test "explains why an email was not requested or cannot be sent" do
      order = fulfillable_order(fulfillment_status: :fulfilled)

      assert %{state: :pending, retry?: true} = Orders.fulfillment_email_status(order)
      assert %{state: :skipped, retry?: false} = Orders.fulfillment_email_status(%{order | skip_delivered_email: true})

      assert %{state: :no_email, retry?: false} =
               Orders.fulfillment_email_status(%{order | customer_email: nil, skip_delivered_email: true})

      assert %{state: :sent, retry?: false, sent_at: %DateTime{}} =
               Orders.fulfillment_email_status(%{order | delivered_emailed_at: DateTime.utc_now()})
    end

    test "shows a photo failure and retries the existing job rather than creating another" do
      order = fulfillable_order([])
      actor = admin()
      {:ok, order} = Orders.mark_order_fulfilled(order, actor: actor)
      assert %{state: :queued, retry?: false} = Orders.fulfillment_email_status(order)

      [job] = all_enqueued(worker: SendDeliveredEmail)

      job
      |> Ecto.Changeset.change(
        state: "retryable",
        attempt: 1,
        scheduled_at: DateTime.add(DateTime.utc_now(), 600),
        errors: [%{"error" => "imgproxy answered 404 for the delivery photo"}]
      )
      |> Edenflowers.Repo.update!()

      assert %{state: :retrying, reason: :photo_unavailable, retry?: true} = Orders.fulfillment_email_status(order)
      assert {:ok, order} = Orders.retry_fulfillment_email(order, actor: actor)
      assert [%{id: id}] = all_enqueued(worker: SendDeliveredEmail)
      assert id == job.id
      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :default)

      order = Orders.get_order_by_id!(order.id, authorize?: false)
      assert %{state: :sent, retry?: false} = Orders.fulfillment_email_status(order)
      assert {:error, _} = Orders.retry_fulfillment_email(order, actor: actor)
    end

    test "retry respects opt-out and admin authorization" do
      order = fulfillable_order(fulfillment_status: :fulfilled, skip_delivered_email: true)
      assert {:error, _} = Orders.retry_fulfillment_email(order, actor: admin())

      order = Ash.Seed.update!(order, %{skip_delivered_email: false})
      assert {:error, _} = Orders.retry_fulfillment_email(order, actor: generate(admin_user(admin: false)))
      refute_enqueued(worker: SendDeliveredEmail)
    end

    test "retry does not revive a discarded job alongside its scheduled replacement" do
      order = fulfillable_order([])
      actor = admin()
      {:ok, order} = Orders.mark_order_fulfilled(order, actor: actor)
      [old_job] = all_enqueued(worker: SendDeliveredEmail)
      old_job |> Ecto.Changeset.change(state: "discarded") |> Edenflowers.Repo.update!()

      perform_job(Edenflowers.Orders.Schedulers.SendDeliveredEmail, %{})
      assert {:ok, _} = Orders.retry_fulfillment_email(order, actor: actor)

      assert [%{id: new_id}] = all_enqueued(worker: SendDeliveredEmail)
      refute new_id == old_job.id
      assert Edenflowers.Repo.get!(Oban.Job, old_job.id).state == "discarded"
      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :default)
      assert_email_sent()
      assert_no_email_sent()
    end
  end

  defp stub_delivery_photo do
    Req.Test.stub(Edenflowers.Orders.Changes.SendDeliveredEmail, fn conn ->
      assert conn.host == "imgproxy.test"
      assert conn.request_path =~ "rs:fit:1600:1600"
      assert conn.request_path =~ "q:80"
      Plug.Conn.send_resp(conn, 200, "small jpeg")
    end)
  end

  describe "marking an order fulfilled" do
    test "queues the delivered email for a delivery order" do
      order = fulfillable_order([])

      {:ok, _order} = Orders.mark_order_fulfilled(order, actor: admin())

      assert_enqueued(worker: SendDeliveredEmail, args: %{"primary_key" => %{"id" => order.id}})
    end

    test "emails collection confirmation for an unpaid custom pickup" do
      order = fulfillable_order(fulfillment_method: :pickup, origin: :custom)

      {:ok, _order} = Orders.mark_order_fulfilled(order, actor: admin())
      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :default)

      assert_email_sent(fn email ->
        assert email.to == [{"", "ada@example.com"}]
        assert email.bcc == [Application.fetch_env!(:edenflowers, :mailer_from_address)]
        assert email.subject == "Your Eden Flowers order 1400 has been collected"
        assert email.text_body =~ "Your order has been collected."
        refute email.text_body =~ "delivered"
        assert email.attachments == []
      end)

      assert Orders.get_order_by_id!(order.id, authorize?: false).delivered_emailed_at
    end

    test "sends nothing to a phone-only customer" do
      order = fulfillable_order(customer_email: nil, customer_phone_number: "+358401234567")

      {:ok, _order} = Orders.mark_order_fulfilled(order, actor: admin())

      refute_enqueued(worker: SendDeliveredEmail)
      assert %{failure: 0} = Oban.drain_queue(queue: :default)
      assert_no_email_sent()
    end

    test "sends nothing when Jennie chose not to email the customer" do
      order = fulfillable_order([])

      {:ok, order} = Orders.mark_order_fulfilled(order, %{email_customer?: false}, actor: admin())

      assert order.fulfillment_status == :fulfilled
      assert order.skip_delivered_email
      refute_enqueued(worker: SendDeliveredEmail)

      perform_job(Edenflowers.Orders.Schedulers.SendDeliveredEmail, %{})
      refute_enqueued(worker: SendDeliveredEmail)
      assert_no_email_sent()
    end

    test "queues nothing when the order is already fulfilled" do
      order = fulfillable_order(fulfillment_status: :fulfilled)

      assert {:error, _} = Orders.mark_order_fulfilled(order, actor: admin())

      refute_enqueued(worker: SendDeliveredEmail)
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
      assert order.skip_delivered_email
      refute order.email_delivery_photo
      assert order.delivery_photo_slug == "local:///uploads/door.jpg"
      refute_enqueued(worker: SendDeliveredEmail)
    end

    test "the domain rejects emailing a delivery photo without a photo" do
      order = fulfillable_order([])

      assert {:error, _} = Orders.mark_order_fulfilled(order, %{email_delivery_photo: true}, actor: admin())
      assert Orders.get_order_by_id!(order.id, authorize?: false).fulfillment_status == :pending
      refute_enqueued(worker: SendDeliveredEmail)
    end
  end

  describe "the trigger" do
    test "tells the customer their gift reached the recipient" do
      order = fulfillable_order(gift: true, recipient_name: "Grace Hopper", fulfillment_status: :fulfilled)

      assert {:ok, _} = perform_job(SendDeliveredEmail, %{"primary_key" => %{"id" => order.id}})

      assert_email_sent(fn email ->
        assert email.to == [{"", "ada@example.com"}]
        assert email.bcc == [Application.fetch_env!(:edenflowers, :mailer_from_address)]
        assert email.subject == "Your Eden Flowers order 1400 has been delivered"
        assert email.text_body =~ "Hi Ada,"
        assert email.text_body =~ "Your order for Grace has been delivered."
      end)

      reloaded = Orders.get_order_by_id!(order.id, authorize?: false)
      assert reloaded.delivered_emailed_at != nil
    end

    test "leaves out the recipient when the order isn't a gift" do
      order =
        fulfillable_order(
          gift: false,
          customer_name: "Sara Smith",
          recipient_name: "Sara Smith",
          fulfillment_status: :fulfilled
        )

      assert {:ok, _} = perform_job(SendDeliveredEmail, %{"primary_key" => %{"id" => order.id}})

      assert_email_sent(fn email ->
        assert email.text_body =~ "Hi Sara,"
        refute email.text_body =~ "Your order for Sara"
        assert email.text_body =~ "Your order has been delivered."
      end)
    end

    test "writes in the order's language" do
      order = fulfillable_order(locale: "sv-FI", fulfillment_status: :fulfilled)

      assert {:ok, _} = perform_job(SendDeliveredEmail, %{"primary_key" => %{"id" => order.id}})

      assert_email_sent(fn email ->
        assert email.subject == "Din Eden Flowers-beställning 1400 har levererats"
        assert email.text_body =~ "Hej Ada,"
        assert email.text_body =~ "Din beställning har levererats."
      end)
    end

    test "recovers an unsent pickup confirmation through the scheduler" do
      order = fulfillable_order(fulfillment_method: :pickup, fulfillment_status: :fulfilled)

      perform_job(Edenflowers.Orders.Schedulers.SendDeliveredEmail, %{})
      assert_enqueued(worker: SendDeliveredEmail, args: %{"primary_key" => %{"id" => order.id}})
      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :default)

      assert_email_sent(fn email -> assert email.text_body =~ "Your order has been collected." end)
      perform_job(Edenflowers.Orders.Schedulers.SendDeliveredEmail, %{})
      refute_enqueued(worker: SendDeliveredEmail)
    end

    test "rechecks eligibility when an already queued job runs" do
      for overrides <- [
            [skip_delivered_email: true],
            [customer_email: nil, customer_phone_number: "+358401234567"],
            [fulfillment_status: :cancelled],
            [fulfillment_status: :pending],
            [state: :payment],
            [delivered_emailed_at: DateTime.utc_now()]
          ] do
        order = fulfillable_order(order_reference: "T#{System.unique_integer([:positive])}")
        {:ok, order} = Orders.mark_order_fulfilled(order, actor: admin())
        Ash.Seed.update!(order, Map.new(overrides))

        assert %{failure: 0} = Oban.drain_queue(queue: :default)
        assert_no_email_sent()
      end
    end

    @tag capture_log: true
    test "a missing opted-in photo does not fall back to a plain confirmation" do
      order = fulfillable_order(fulfillment_status: :fulfilled, email_delivery_photo: true)

      assert_raise Ash.Error.Invalid, ~r/Delivery photo is missing/, fn ->
        perform_job(SendDeliveredEmail, %{"primary_key" => %{"id" => order.id}})
      end

      assert_no_email_sent()
      assert Orders.get_order_by_id!(order.id, authorize?: false).delivered_emailed_at == nil
    end

    @tag capture_log: true
    test "retries photo failures without marking the confirmation sent" do
      Req.Test.stub(Edenflowers.Orders.Changes.SendDeliveredEmail, fn conn ->
        Plug.Conn.send_resp(conn, 503, "unavailable")
      end)

      order =
        fulfillable_order(
          delivery_photo_slug: "local:///uploads/door.jpg",
          email_delivery_photo: true
        )

      actor = admin()
      assert {:ok, order} = Orders.mark_order_fulfilled(order, actor: actor)
      assert %{failure: 1} = Oban.drain_queue(queue: :default)
      assert %{state: :retrying, reason: :photo_unavailable} = Orders.fulfillment_email_status(order)

      assert_no_email_sent()
      assert Orders.get_order_by_id!(order.id, authorize?: false).delivered_emailed_at == nil

      stub_delivery_photo()
      assert {:ok, _} = Orders.retry_fulfillment_email(order, actor: actor)
      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :default)
      assert_email_sent(fn email -> assert [%{data: "small jpeg"}] = email.attachments end)
      assert Orders.get_order_by_id!(order.id, authorize?: false).delivered_emailed_at
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

      assert {:ok, _} = perform_job(SendDeliveredEmail, %{"primary_key" => %{"id" => order.id}})

      assert_email_sent(fn email ->
        assert email.subject == "Your Eden Flowers order 1400 was left for you"
        assert email.text_body =~ "Nobody was home"
        assert email.text_body =~ "I delivered your order, so I left it in the spot shown in the attached photo."
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

      assert {:ok, _} = perform_job(SendDeliveredEmail, %{"primary_key" => %{"id" => order.id}})

      assert_email_sent(fn email ->
        assert email.text_body =~ "Your order for Grace was delivered while nobody was home"
      end)
    end

    test "sends the usual email when Jennie chose not to send the photo" do
      order =
        fulfillable_order(
          fulfillment_status: :fulfilled,
          delivery_photo_slug: "local:///uploads/door.jpg",
          email_delivery_photo: false
        )

      assert {:ok, _} = perform_job(SendDeliveredEmail, %{"primary_key" => %{"id" => order.id}})

      assert_email_sent(fn email ->
        assert email.text_body =~ "Your order has been delivered."
        assert email.attachments == []
      end)
    end

    test "doesn't send an order Jennie chose not to email, whoever asks" do
      order = fulfillable_order(fulfillment_status: :fulfilled, skip_delivered_email: true)

      assert {:ok, reloaded} = Ash.update(order, %{}, action: :send_delivered_email, authorize?: false)

      assert_no_email_sent()
      assert reloaded.delivered_emailed_at == nil
    end

    test "collection confirmation uses the customer's locale, not the worker's" do
      for {locale, reference, subject, greeting, body} <- [
            {"sv-FI", "1400", "Din Eden Flowers-beställning 1400 har hämtats", "Hej Ada,",
             "Din beställning har hämtats."},
            {"fi", "1401", "Eden Flowers -tilauksesi 1401 on noudettu", "Hei Ada,", "Tilauksesi on noudettu."}
          ] do
        order =
          fulfillable_order(
            fulfillment_method: :pickup,
            fulfillment_status: :fulfilled,
            locale: locale,
            order_reference: reference
          )

        assert {:ok, _} = perform_job(SendDeliveredEmail, %{"primary_key" => %{"id" => order.id}})

        assert_email_sent(fn email ->
          assert email.subject == subject
          assert email.text_body =~ greeting
          assert email.text_body =~ body
        end)
      end
    end

    test "direct action calls also respect eligibility" do
      for overrides <- [
            [fulfillment_status: :pending],
            [fulfillment_status: :cancelled],
            [state: :payment],
            [customer_email: nil, customer_phone_number: "+358401234567"],
            [delivered_emailed_at: DateTime.utc_now()]
          ] do
        order =
          fulfillable_order(
            Keyword.merge(
              [fulfillment_status: :fulfilled, order_reference: "T#{System.unique_integer([:positive])}"],
              overrides
            )
          )

        assert {:ok, _} = Ash.update(order, %{}, action: :send_delivered_email, authorize?: false)
        assert_no_email_sent()
      end
    end

    test "direct action calls recheck a recorded send even when passed the original order" do
      order = fulfillable_order(fulfillment_status: :fulfilled)

      assert {:ok, _} = Ash.update(order, %{}, action: :send_delivered_email, authorize?: false)
      assert_email_sent()
      assert {:ok, _} = Ash.update(order, %{}, action: :send_delivered_email, authorize?: false)
      assert_no_email_sent()

      versions = Ash.load!(order, :paper_trail_versions, authorize?: false).paper_trail_versions
      assert Enum.count(versions, &(&1.version_action_name == :send_delivered_email)) == 1
    end

    test "direct action calls recheck a persisted opt-out even when passed a stale order" do
      order = fulfillable_order(fulfillment_status: :fulfilled)
      Ash.Seed.update!(order, %{skip_delivered_email: true})

      assert {:ok, reloaded} = Ash.update(order, %{}, action: :send_delivered_email, authorize?: false)
      assert reloaded.skip_delivered_email
      assert reloaded.delivered_emailed_at == nil
      assert_no_email_sent()

      versions = Ash.load!(order, :paper_trail_versions, authorize?: false).paper_trail_versions
      refute Enum.any?(versions, &(&1.version_action_name == :send_delivered_email))
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
