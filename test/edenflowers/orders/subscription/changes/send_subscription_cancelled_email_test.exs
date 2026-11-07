defmodule Edenflowers.Orders.Subscription.Changes.SendSubscriptionCancelledEmailTest do
  use Edenflowers.DataCase, async: true

  import Generator
  import Swoosh.TestAssertions

  alias Edenflowers.Email.Preview
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Workers.SendSubscriptionCancelledEmail

  test "names the delivery already charged that still comes" do
    {:ok, customer} = Edenflowers.Accounts.upsert_user("ada@example.com", "Ada Lovelace", authorize?: false)
    subscription = generate(subscription(user_id: customer.id, locale: "en-GB"))
    charged_for = Date.add(Edenflowers.ShopTime.today(), 2)

    placed_order(
      subscription_id: subscription.id,
      origin: :subscription,
      fulfillment_date: charged_for,
      paid: true
    )

    {:ok, _cancelled} = Orders.cancel_subscription(subscription, actor: generate(admin_user()))

    assert %{success: 1} = Oban.drain_queue(queue: :default, with_scheduled: true)

    assert_email_sent(fn email ->
      assert email.subject =~ "subscription is cancelled"

      assert email.text_body =~
               "Your delivery on #{Edenflowers.Format.weekday_date(charged_for, "en-GB")} will still come."
    end)
  end

  test "the preview names only an order past its change deadline and does not claim an unpaid order was charged" do
    {:ok, customer} = Edenflowers.Accounts.upsert_user("ada@example.com", "Ada Lovelace", authorize?: false)
    subscription = generate(subscription(user_id: customer.id, locale: "en-GB"))
    date = Date.add(Edenflowers.ShopTime.today(), 2)
    placed_order(subscription_id: subscription.id, origin: :subscription, fulfillment_date: date)

    preview = Preview.build(:subscription_cancelled, subscription, %{})
    assert preview.text_body =~ "Your delivery on #{Edenflowers.Format.weekday_date(date, "en-GB")} will still come."
    refute preview.text_body =~ "already charged"

    other = generate(subscription(user_id: customer.id, locale: "en-GB"))

    placed_order(
      subscription_id: other.id,
      origin: :subscription,
      fulfillment_date: Date.add(Edenflowers.ShopTime.today(), 14)
    )

    preview = Preview.build(:subscription_cancelled, other, %{})
    refute preview.text_body =~ "will still come"
  end

  test "Jennie's rewrite of the email goes out from the queued job" do
    {:ok, customer} = Edenflowers.Accounts.upsert_user("ada@example.com", "Ada Lovelace", authorize?: false)
    subscription = generate(subscription(user_id: customer.id, locale: "en-GB"))
    edits = %{subject: "Thank you, Ada", body: "Thank you for a lovely year.\n\nJennie"}

    {:ok, _cancelled} = Orders.cancel_subscription(subscription, edits, actor: generate(admin_user()))

    assert %{success: 1} = Oban.drain_queue(queue: :default, with_scheduled: true)

    assert_email_sent(fn email ->
      assert email.subject == "Thank you, Ada"
      assert email.text_body == "Thank you for a lovely year.\n\nJennie"
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
