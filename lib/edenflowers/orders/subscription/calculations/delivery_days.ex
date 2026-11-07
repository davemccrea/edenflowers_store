defmodule Edenflowers.Orders.Subscription.Calculations.DeliveryDays do
  @moduledoc """
  The weekdays a subscription can move to: those the shop calendar opens,
  plus the one it delivers on now. Jennie may since have closed that weekday,
  and keeping it means a subscriber can still change their size or interval
  without being moved to another day.
  """
  use Ash.Resource.Calculation

  alias Edenflowers.Fulfillment
  alias Edenflowers.Fulfillment.Weekday

  @impl true
  def load(_query, _opts, _context), do: [:next_fulfillment_date]

  @impl true
  def calculate(subscriptions, _opts, _context) do
    open_days = Fulfillment.get_shop_calendar!(authorize?: false).available_days

    Enum.map(subscriptions, fn subscription ->
      current = Weekday.from_date(subscription.next_fulfillment_date)
      Enum.filter(Weekday.all(), &(&1 in open_days or &1 == current))
    end)
  end
end
