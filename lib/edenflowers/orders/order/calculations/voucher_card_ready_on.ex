defmodule Edenflowers.Orders.Order.Calculations.VoucherCardReadyOn do
  @moduledoc """
  The day a Gift voucher sale's gift card is ready to collect: the first day the
  shop opens after the order, so Jennie has time to write the card. Counted from
  when it was ordered, so the confirmation page and the email name the same day.
  """
  use Ash.Resource.Calculation

  alias Edenflowers.Fulfillment
  alias Edenflowers.ShopTime

  @impl true
  def load(_query, _opts, _context), do: [:collect_voucher_card, :ordered_at]

  @impl true
  def calculate(orders, _opts, _context) do
    calendar = if Enum.any?(orders, & &1.collect_voucher_card), do: Fulfillment.get_shop_calendar!(authorize?: false)
    Enum.map(orders, &ready_on(&1, calendar))
  end

  defp ready_on(%{collect_voucher_card: true} = order, calendar) do
    ordered_at = order.ordered_at || DateTime.utc_now()
    Fulfillment.Availability.next_open_date(calendar, ordered_at, Date.add(ShopTime.today(ordered_at), 1))
  end

  defp ready_on(_order, _calendar), do: nil
end
