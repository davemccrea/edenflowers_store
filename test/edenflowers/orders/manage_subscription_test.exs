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

  defp subscription(context, attrs \\ %{}) do
    Ash.Seed.seed!(
      Subscription,
      Map.merge(
        %{
          user_id: context.customer.id,
          product_variant_id: context.variant_id,
          fulfillment_option_id: context.fulfillment_option_id,
          interval_weeks: 2,
          next_fulfillment_date: days_from_today(14),
          locale: "en",
          stripe_customer_id: "cus_1",
          stripe_payment_method_id: "pm_1"
        },
        attrs
      )
    )
  end

  defp days_from_today(days), do: Date.add(HelsinkiToday.today(), days)

  test "lists only the customer's own subscriptions", context do
    mine = subscription(context)
    _theirs = subscription(context, %{user_id: generate(admin_user(admin: false)).id})

    assert [%{id: id}] = Orders.list_my_subscriptions!(actor: context.customer)
    assert id == mine.id
  end

  test "a customer can't act on someone else's subscription", context do
    theirs = subscription(context, %{user_id: generate(admin_user(admin: false)).id})

    for action <- [:skip_subscription, :pause_subscription, :cancel_subscription] do
      assert {:error, %Ash.Error.Forbidden{}} = apply(Orders, action, [theirs, [actor: context.customer]])
    end

    paused = subscription(context, %{user_id: theirs.user_id, state: :paused})
    assert {:error, %Ash.Error.Forbidden{}} = Orders.resume_subscription(paused, actor: context.customer)
  end

  test "skip adds the next date to skipped_dates", context do
    subscription = subscription(context)

    skipped = Orders.skip_subscription!(subscription, actor: context.customer)

    assert skipped.skipped_dates == [subscription.next_fulfillment_date]
    assert skipped.next_fulfillment_date == subscription.next_fulfillment_date
  end

  test "pause stops occurrences being created", context do
    subscription = subscription(context, %{next_fulfillment_date: days_from_today(2)})

    assert Orders.pause_subscription!(subscription, actor: context.admin).state == :paused

    assert :ok = perform_job(Edenflowers.Orders.Schedulers.CreateOccurrence, %{})
    assert all_enqueued(worker: Edenflowers.Orders.Workers.CreateOccurrence) == []
  end

  test "resume picks the next date on the schedule outside the lead window", context do
    subscription = subscription(context, %{state: :paused, next_fulfillment_date: days_from_today(-11)})

    resumed = Orders.resume_subscription!(subscription, actor: context.customer)

    assert resumed.state == :active
    assert resumed.next_fulfillment_date == days_from_today(17)
  end

  test "resume keeps a next date that is still far enough away", context do
    subscription = subscription(context, %{state: :paused, next_fulfillment_date: days_from_today(4)})

    assert Orders.resume_subscription!(subscription, actor: context.customer).next_fulfillment_date ==
             days_from_today(4)
  end

  test "cancel is final", context do
    cancelled = context |> subscription() |> Orders.cancel_subscription!(actor: context.customer)

    assert cancelled.state == :cancelled
    assert {:error, _} = Orders.resume_subscription(cancelled, actor: context.customer)
    assert {:error, _} = Orders.pause_subscription(cancelled, actor: context.customer)
    assert {:error, _} = Orders.skip_subscription(cancelled, actor: context.customer)
  end

  test "a held subscription can be cancelled but not paused", context do
    subscription = subscription(context, %{state: :payment_failed, next_fulfillment_date: days_from_today(1)})

    assert {:error, _} = Orders.pause_subscription(subscription, actor: context.customer)
    assert Orders.cancel_subscription!(subscription, actor: context.customer).state == :cancelled
  end

  describe "the 24-hour cutoff" do
    test "closes changes the day before the occurrence is created", context do
      assert %{changes_closed?: false} =
               Ash.load!(subscription(context, %{next_fulfillment_date: days_from_today(5)}), :changes_closed?)

      assert %{changes_closed?: true} =
               Ash.load!(subscription(context, %{next_fulfillment_date: days_from_today(4)}), :changes_closed?)
    end

    test "refuses a customer's skip, pause and cancel", context do
      subscription = subscription(context, %{next_fulfillment_date: days_from_today(4)})

      for action <- [:skip_subscription, :pause_subscription, :cancel_subscription] do
        assert {:error, %Ash.Error.Invalid{errors: [%{message: "It's too late to change your next delivery."}]}} =
                 apply(Orders, action, [subscription, [actor: context.customer]])
      end
    end

    test "doesn't apply to Jennie", context do
      subscription = subscription(context, %{next_fulfillment_date: days_from_today(4)})

      assert Orders.skip_subscription!(subscription, actor: context.admin).skipped_dates ==
               [subscription.next_fulfillment_date]

      assert Orders.pause_subscription!(subscription, actor: context.admin).state == :paused
    end

    test "doesn't stop a paused subscription being cancelled", context do
      subscription = subscription(context, %{state: :paused, next_fulfillment_date: days_from_today(1)})

      assert Orders.cancel_subscription!(subscription, actor: context.customer).state == :cancelled
    end
  end
end
