defmodule Edenflowers.Orders.Calculations.ScheduledDate do
  @moduledoc """
  The first date on a Subscription's schedule at least `days_from_today` days
  after today, as `Changes.StepToScheduledDate` would move it to.
  """
  use Ash.Resource.Calculation

  alias Edenflowers.Orders.Changes.StepToScheduledDate

  @impl true
  def load(_query, _opts, _context), do: [:next_fulfillment_date, :interval_weeks]

  @impl true
  def calculate(subscriptions, opts, _context) do
    Enum.map(subscriptions, fn subscription ->
      StepToScheduledDate.scheduled_date(
        subscription.next_fulfillment_date,
        subscription.interval_weeks,
        Keyword.fetch!(opts, :days_from_today)
      )
    end)
  end
end
