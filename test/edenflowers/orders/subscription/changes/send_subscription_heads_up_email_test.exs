defmodule Edenflowers.Orders.Subscription.Changes.SendSubscriptionHeadsUpEmailTest do
  use Edenflowers.DataCase, async: true
  import Generator
  import Swoosh.TestAssertions

  alias Edenflowers.Orders
  alias Edenflowers.Orders.Schedulers.SendSubscriptionHeadsUpEmail, as: ScheduleHeadsUps
  alias Edenflowers.Orders.Subscription
  alias Edenflowers.Orders.Workers.SendSubscriptionHeadsUpEmail

  test "a 2-week subscription gets one heads-up 4 days before a delivery" do
    user = generate(admin_user(admin: false, email: "maria@example.com"))

    variant =
      generate(product_variant(product_id: generate(product(name: "Florist's choice")).id, price: Decimal.new("59.00")))

    subscription =
      generate(
        subscription(
          user_id: user.id,
          product_variant_id: variant.id,
          next_fulfillment_date: days_from_today(4),
          delivery_address: "Esplanadi 1, Helsinki"
        )
      )

    assert scheduled_heads_ups() == [subscription.id]

    assert {:ok, _subscription} =
             perform_job(SendSubscriptionHeadsUpEmail, %{"primary_key" => %{"id" => subscription.id}})

    assert_email_sent(fn email ->
      assert email.to == [{"", "maria@example.com"}]
      assert email.from == {"Eden Flowers", "info@edenflowers.fi"}
      assert email.subject =~ ~r/^Your next flowers come on \w+ \d+\.\d+\.$/
      assert email.text_body =~ ~r/Your next Florist's choice delivery is on .+, to Esplanadi 1, Helsinki\./
      assert email.text_body =~ "in your account by #{weekday_date(days_from_today(1))}:"
      assert email.text_body =~ "Your card will be charged €59.00 on #{weekday_date(days_from_today(2))}."
    end)

    assert Ash.get!(Subscription, subscription.id, authorize?: false).heads_up_emailed_for == days_from_today(4)
    Edenflowers.Repo.delete_all(Oban.Job)
    assert scheduled_heads_ups() == []
  end

  test "weekly, paused, and deliveries outside the window or after changes close get none" do
    generate(subscription(interval_weeks: 1, next_fulfillment_date: days_from_today(4)))
    generate(subscription(state: :paused, next_fulfillment_date: days_from_today(4)))
    generate(subscription(state: :payment_failed, next_fulfillment_date: days_from_today(4)))
    generate(subscription(next_fulfillment_date: days_from_today(5)))
    generate(subscription(interval_weeks: 4, next_fulfillment_date: days_from_today(2)))

    assert scheduled_heads_ups() == []
  end

  test "resuming into the window doesn't send one" do
    subscription = generate(subscription(state: :paused, next_fulfillment_date: days_from_today(3)))

    Orders.resume_subscription!(subscription, authorize?: false)

    assert scheduled_heads_ups() == []
  end

  defp days_from_today(days), do: Date.add(Edenflowers.ShopTime.today(), days)

  defp weekday_date(date), do: Edenflowers.Format.weekday_date(date, "en")

  defp scheduled_heads_ups do
    assert :ok = perform_job(ScheduleHeadsUps, %{})
    for job <- all_enqueued(worker: SendSubscriptionHeadsUpEmail), do: job.args["primary_key"]["id"]
  end
end
