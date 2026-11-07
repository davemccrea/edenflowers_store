defmodule Edenflowers.Orders.Subscription.Calculations.ClosedDeliveryDates do
  @moduledoc """
  The scheduled delivery dates in the next 8 weeks that fall on a day the
  shop calendar closes. An Occurrence is made for its scheduled date whatever
  the calendar says, so Jennie sees these to decide whether to deliver anyway
  or move the order to another day once it's booked. Only an active
  subscription delivers, so any other has none.
  """
  use Ash.Resource.Calculation

  alias Edenflowers.Fulfillment
  alias Edenflowers.Fulfillment.Availability
  alias Edenflowers.Orders.Subscription

  @weeks_ahead 8

  @impl true
  def load(_query, _opts, _context), do: [:state, :next_fulfillment_date, :interval_weeks]

  @impl true
  def calculate(subscriptions, _opts, _context) do
    calendar = Fulfillment.get_shop_calendar!(authorize?: false)
    now = Edenflowers.ShopTime.now()
    until = Date.add(DateTime.to_date(now), @weeks_ahead * 7)

    Enum.map(subscriptions, fn
      %{state: state} when state != :active ->
        []

      subscription ->
        subscription.next_fulfillment_date
        |> Stream.iterate(&Subscription.next_date(&1, subscription.interval_weeks))
        |> Enum.take_while(&(Date.compare(&1, until) != :gt))
        |> Enum.filter(&closed?(calendar, &1, now))
    end)
  end

  defp closed?(calendar, date, now),
    do: Availability.unavailable_reason(calendar, date, now) in [:date_disabled, :weekday_disabled]
end
