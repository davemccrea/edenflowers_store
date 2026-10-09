defmodule Edenflowers.Orders.ManageSubscriptionTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Expressions.HelsinkiToday
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Subscription

  setup do
    %{
      customer: generate(admin_user(admin: false)),
      admin: generate(admin_user()),
      variant_id: generate(product_variant(product_id: generate(product()).id)).id,
      fulfillment_option_id: generate(fulfillment_option(fulfillment_method: :delivery)).id
    }
  end

  defp subscription_for(context, attrs \\ []) do
    defaults = [
      user_id: context.customer.id,
      product_variant_id: context.variant_id,
      fulfillment_option_id: context.fulfillment_option_id
    ]

    generate(subscription(Keyword.merge(defaults, attrs)))
  end

  defp days_from_today(days), do: Date.add(HelsinkiToday.today(), days)

  defp occurrence(subscription, days) do
    generate(
      order(
        state: :placed,
        origin: :subscription,
        subscription_id: subscription.id,
        subscription_date: days_from_today(days),
        fulfillment_date: days_from_today(days)
      )
    )
  end

  test "lists only the customer's own subscriptions", context do
    mine = subscription_for(context)
    _theirs = subscription_for(context, user_id: generate(admin_user(admin: false)).id)

    assert [%{id: id}] = Orders.list_my_subscriptions!(actor: context.customer)
    assert id == mine.id
  end

  test "a customer can't act on someone else's subscription", context do
    theirs = subscription_for(context, user_id: generate(admin_user(admin: false)).id)

    for action <- [:pause_subscription, :cancel_subscription] do
      assert {:error, %Ash.Error.Forbidden{}} = apply(Orders, action, [theirs, [actor: context.customer]])
    end

    paused = subscription_for(context, user_id: theirs.user_id, state: :paused)
    assert {:error, %Ash.Error.Forbidden{}} = Orders.resume_subscription(paused, actor: context.customer)
  end

  test "pause stops occurrences being created", context do
    subscription = subscription_for(context, next_fulfillment_date: days_from_today(2))

    assert Orders.pause_subscription!(subscription, actor: context.admin).state == :paused

    assert :ok = perform_job(Edenflowers.Orders.Schedulers.CreateOccurrence, %{})
    assert all_enqueued(worker: Edenflowers.Orders.Workers.CreateOccurrence) == []
  end

  test "resume picks the next date on the schedule outside the lead window", context do
    subscription = subscription_for(context, state: :paused, next_fulfillment_date: days_from_today(-11))

    resumed = Orders.resume_subscription!(subscription, actor: context.customer)

    assert resumed.state == :active
    assert resumed.next_fulfillment_date == days_from_today(17)
  end

  test "resume keeps a next date that is still far enough away", context do
    subscription = subscription_for(context, state: :paused, next_fulfillment_date: days_from_today(4))

    assert Orders.resume_subscription!(subscription, actor: context.customer).next_fulfillment_date ==
             days_from_today(4)
  end

  test "cancel is final", context do
    cancelled = context |> subscription_for() |> Orders.cancel_subscription!(actor: context.customer)

    assert cancelled.state == :cancelled
    assert {:error, _} = Orders.resume_subscription(cancelled, actor: context.customer)
    assert {:error, _} = Orders.pause_subscription(cancelled, actor: context.customer)
  end

  test "cancel also cancels a future occurrence while customer changes are open", context do
    subscription = subscription_for(context)
    occurrence = occurrence(subscription, 5)
    payment = generate(payment(order_id: occurrence.id))

    assert Orders.cancel_subscription!(subscription, actor: context.customer).state == :cancelled
    assert Ash.reload!(occurrence, authorize?: false).fulfillment_status == :cancelled
    assert Ash.get!(Edenflowers.Orders.Payment, payment.id, authorize?: false).amount == payment.amount
  end

  test "cancel leaves a booked occurrence in place after its customer-change deadline", context do
    subscription = subscription_for(context)
    occurrence = occurrence(subscription, 4)

    assert Orders.cancel_subscription!(subscription, actor: context.customer).state == :cancelled
    assert Ash.reload!(occurrence, authorize?: false).fulfillment_status == :pending
  end

  test "cancel stops subsequent occurrences even inside the next delivery cutoff", context do
    subscription = subscription_for(context, next_fulfillment_date: days_from_today(2))

    assert Orders.cancel_subscription!(subscription, actor: context.customer).state == :cancelled
    assert :ok = perform_job(Edenflowers.Orders.Schedulers.CreateOccurrence, %{})
    assert all_enqueued(worker: Edenflowers.Orders.Workers.CreateOccurrence) == []
  end

  test "a stale active subscription cannot pause after cancellation", context do
    stale_subscription = subscription_for(context)

    assert Orders.cancel_subscription!(stale_subscription, actor: context.customer).state == :cancelled
    assert {:error, _} = Orders.pause_subscription(stale_subscription, actor: context.customer)
    assert Ash.get!(Subscription, stale_subscription.id, actor: context.customer).state == :cancelled
  end

  test "a held subscription can be cancelled but not paused", context do
    subscription = subscription_for(context, state: :payment_failed, next_fulfillment_date: days_from_today(1))

    assert {:error, _} = Orders.pause_subscription(subscription, actor: context.customer)
    assert Orders.cancel_subscription!(subscription, actor: context.customer).state == :cancelled
  end

  describe "the 24-hour cutoff" do
    test "closes changes the day before the occurrence is created", context do
      assert %{changes_closed?: false} =
               Ash.load!(subscription_for(context, next_fulfillment_date: days_from_today(5)), :changes_closed?)

      assert %{changes_closed?: true} =
               Ash.load!(subscription_for(context, next_fulfillment_date: days_from_today(4)), :changes_closed?)
    end

    test "refuses a customer's pause but still lets them end subsequent deliveries", context do
      subscription = subscription_for(context, next_fulfillment_date: days_from_today(4))

      assert {:error, %Ash.Error.Invalid{errors: [%{message: "It's too late to change your next delivery."}]}} =
               Orders.pause_subscription(subscription, actor: context.customer)

      assert Orders.cancel_subscription!(subscription, actor: context.customer).state == :cancelled
    end

    test "doesn't apply to Jennie", context do
      subscription = subscription_for(context, next_fulfillment_date: days_from_today(4))

      assert Orders.pause_subscription!(subscription, actor: context.admin).state == :paused
    end

    test "doesn't stop a paused subscription being cancelled", context do
      subscription = subscription_for(context, state: :paused, next_fulfillment_date: days_from_today(1))

      assert Orders.cancel_subscription!(subscription, actor: context.customer).state == :cancelled
    end
  end
end
