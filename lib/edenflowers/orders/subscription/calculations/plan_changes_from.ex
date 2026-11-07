defmodule Edenflowers.Orders.Subscription.Calculations.PlanChangesFrom do
  @moduledoc """
  The first unbooked delivery a plan change applies to. A paused subscription
  quotes when it would resume today, without promising to restart it.
  """
  use Ash.Resource.Calculation

  alias Edenflowers.Orders.Subscription
  alias Edenflowers.Orders.Subscription.Changes.StepToScheduledDate

  @impl true
  def load(_query, _opts, _context), do: [:state, :next_fulfillment_date, :interval_weeks]

  @impl true
  def calculate(subscriptions, _opts, _context) do
    Enum.map(subscriptions, &date/1)
  end

  @doc false
  def date(%{state: :paused} = subscription) do
    StepToScheduledDate.scheduled_date(
      subscription.next_fulfillment_date,
      subscription.interval_weeks,
      Subscription.change_deadline_days()
    )
  end

  def date(subscription), do: subscription.next_fulfillment_date
end
