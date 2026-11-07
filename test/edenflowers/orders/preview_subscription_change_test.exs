defmodule Edenflowers.Orders.PreviewSubscriptionChangeTest do
  use Edenflowers.DataCase, async: false

  import Generator

  alias Edenflowers.Orders
  alias Edenflowers.Orders.Subscription
  alias Edenflowers.ShopTime

  setup do
    %{user: generate(admin_user(admin: false))}
  end

  test "previews interval and weekday together from the latest delivery without saving", %{user: user} do
    next = Date.add(ShopTime.today(), 28)
    subscription = generate(subscription(user_id: user.id, interval_weeks: 4, next_fulfillment_date: next))
    last = Date.add(next, -14)
    Ash.Seed.update!(generate(order(state: :placed, fulfillment_date: last)), %{subscription_id: subscription.id})

    day = Edenflowers.Fulfillment.Weekday.from_date(Date.add(next, 1))
    params = %{"interval_weeks" => "2", "delivery_day" => to_string(day)}

    assert {:ok, date} = Subscription.preview_plan_change(subscription, params, actor: user)
    assert date == Date.add(next, 1)
    assert Ash.reload!(subscription, authorize?: false).next_fulfillment_date == next

    changed = Orders.change_subscription!(subscription, params, actor: user)
    assert changed.next_fulfillment_date == date
  end

  test "moves a preview inside the change window along the new schedule", %{user: user} do
    subscription =
      generate(subscription(user_id: user.id, interval_weeks: 4, next_fulfillment_date: Date.add(ShopTime.today(), 23)))

    assert {:ok, date} = Subscription.preview_plan_change(subscription, %{interval_weeks: 1}, actor: user)
    assert date == Date.add(ShopTime.today(), 9)
    assert Orders.change_subscription!(subscription, %{interval_weeks: 1}, actor: user).next_fulfillment_date == date
  end

  test "a size-only preview keeps the date, and a paused preview agrees with resuming", %{user: user} do
    for state <- [:active, :paused] do
      next = Date.add(ShopTime.today(), if(state == :paused, do: -30, else: 14))
      subscription = generate(subscription(user_id: user.id, state: state, next_fulfillment_date: next))
      variant = Ash.get!(Edenflowers.Catalog.ProductVariant, subscription.product_variant_id)
      large = generate(product_variant(product_id: variant.product_id, size: :large, draft: false))
      params = %{product_variant_id: large.id}

      # The account resource already has the old resume date loaded.
      loaded = Ash.load!(subscription, [:resume_date, :plan_changes_from], authorize?: false)
      assert {:ok, date} = Subscription.preview_plan_change(loaded, params, actor: user)
      changed = Orders.change_subscription!(subscription, params, actor: user, load: [:plan_changes_from])
      assert changed.plan_changes_from == date
      assert changed.state == state
      assert changed.next_fulfillment_date == next

      if state == :paused do
        assert Date.compare(date, ShopTime.today()) == :gt
        assert Orders.resume_subscription!(changed, actor: user).next_fulfillment_date == date
      else
        assert date == next
      end
    end
  end

  test "recalculates a loaded paused date when the schedule changes", %{user: user} do
    subscription =
      generate(subscription(user_id: user.id, state: :paused, next_fulfillment_date: Date.add(ShopTime.today(), -30)))
      |> Ash.load!([:resume_date, :plan_changes_from], authorize?: false)

    assert {:ok, date} = Subscription.preview_plan_change(subscription, %{interval_weeks: 4}, actor: user)
    changed = Orders.change_subscription!(subscription, %{interval_weeks: 4}, actor: user, load: [:plan_changes_from])
    assert changed.plan_changes_from == date
    assert Orders.resume_subscription!(changed, actor: user).next_fulfillment_date == date
  end

  test "invalid and closed changes return an error rather than a date", %{user: user} do
    subscription = generate(subscription(user_id: user.id))

    for interval <- ["3", "", "invalid"] do
      assert {:error, _} = Subscription.preview_plan_change(subscription, %{interval_weeks: interval}, actor: user)
    end

    closed = generate(subscription(user_id: user.id, next_fulfillment_date: Date.add(ShopTime.today(), 2)))
    assert {:error, _} = Subscription.preview_plan_change(closed, %{interval_weeks: 4}, actor: user)
  end
end
