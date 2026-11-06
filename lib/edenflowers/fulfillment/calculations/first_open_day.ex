defmodule Edenflowers.Fulfillment.Calculations.FirstOpenDay do
  @moduledoc """
  The first day on or after a record's Available from that the shop calendar
  is open, so "Available from" never names a day Jennie has closed. Nil when
  nothing waits. Falls back to the Available from itself when the shop stays
  closed for the 60 days after it.
  """
  use Ash.Resource.Calculation

  alias Edenflowers.Fulfillment
  alias Edenflowers.Fulfillment.Availability

  @impl true
  def load(_query, opts, _context), do: [opts[:from]]

  @impl true
  def calculate(records, opts, _context) do
    from = opts[:from]
    calendar = if Enum.any?(records, &Map.get(&1, from)), do: Fulfillment.get_shop_calendar!(authorize?: false)
    Enum.map(records, &first_open_day(Map.get(&1, from), calendar))
  end

  defp first_open_day(nil, _calendar), do: nil

  defp first_open_day(available_from, calendar),
    do: Availability.next_open_date(calendar, Edenflowers.ShopTime.now(), available_from) || available_from
end
