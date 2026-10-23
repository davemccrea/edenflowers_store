defmodule Edenflowers.Orders.Changes.SendSubscriptionCancelledEmailTest do
  use Edenflowers.DataCase, async: true

  import Generator
  import Swoosh.TestAssertions

  alias Edenflowers.Orders
  alias Edenflowers.Orders.Workers.SendSubscriptionCancelledEmail

  test "names the delivery already charged that still comes, with Jennie's message" do
    {:ok, customer} = Edenflowers.Accounts.upsert_user("ada@example.com", "Ada Lovelace", authorize?: false)
    subscription = generate(subscription(user_id: customer.id, locale: "en-GB"))
    charged_for = Date.add(Edenflowers.ShopTime.today(), 2)

    placed_order(
      subscription_id: subscription.id,
      origin: :subscription,
      fulfillment_date: charged_for,
      paid: true
    )

    {:ok, _cancelled} =
      Orders.cancel_subscription(subscription, %{message: "Thank you for a lovely year."},
        actor: generate(admin_user())
      )

    assert %{success: 1} = Oban.drain_queue(queue: :default, with_scheduled: true)

    assert_email_sent(fn email ->
      assert email.subject =~ "subscription is cancelled"
      assert email.text_body =~ "You won't be charged again.\n\nThank you for a lovely year.\n\n"

      assert email.text_body =~
               "Any delivery already charged will still come on #{Edenflowers.Format.weekday_date(charged_for, "en-GB")}."
    end)
  end

  test "a customer's own cancellation is confirmed matter-of-factly, and Jennie gets a shop notice" do
    {:ok, customer} = Edenflowers.Accounts.upsert_user("ada@example.com", "Ada Lovelace", authorize?: false)
    subscription = generate(subscription(user_id: customer.id, locale: "en-GB"))

    {:ok, _cancelled} = Orders.cancel_subscription(subscription, actor: customer)

    refute_enqueued(worker: SendSubscriptionCancelledEmail)

    assert_enqueued(
      worker: Edenflowers.Orders.Workers.EmailShop,
      args: %{"notice" => "cancelled", "subscription_id" => subscription.id}
    )

    Oban.drain_queue(queue: :default, with_scheduled: true)

    assert_email_sent(fn email ->
      assert {"Eden Flowers", _address} = email.from
      assert email.bcc == [{"Jennie", "info+copy@edenflowers.fi"}]
      refute email.text_body =~ "already been charged"
      assert email.text_body =~ "subscription is cancelled. Your card won't be charged again."
    end)

    assert_email_sent(fn email ->
      assert email.subject == "Prenumeration avslutad av kunden"
      assert email.text_body =~ "/admin/subscriptions/#{subscription.id}"
    end)
  end

  test "pausing, resuming and changing send nothing" do
    {:ok, customer} = Edenflowers.Accounts.upsert_user("ada@example.com", "Ada Lovelace", authorize?: false)
    subscription = generate(subscription(user_id: customer.id))

    {:ok, paused} = Orders.pause_subscription(subscription, actor: customer)
    {:ok, _resumed} = Orders.resume_subscription(paused, actor: customer)

    Oban.drain_queue(queue: :default, with_scheduled: true)
    assert_no_email_sent()
  end
end
