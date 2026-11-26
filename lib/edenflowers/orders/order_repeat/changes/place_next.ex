defmodule Edenflowers.Orders.OrderRepeat.Changes.PlaceNext do
  @moduledoc """
  Places a copy of the repeat's latest order for `next_on`, and moves
  `next_on` on, in one transaction so a date is never placed twice.

  The copy is placed like Jennie would place it: its own payment link, stock
  and delivery fee, catalogue items at their current price, her own items at
  hers. It sends no Order details email and spends no Gift voucher.
  """
  use Ash.Resource.Change

  alias Edenflowers.Orders.Order

  @impl true
  def change(changeset, _opts, context) do
    weeks = changeset.data.every_weeks
    date = catch_up(changeset.data.next_on, weeks)

    changeset
    |> Ash.Changeset.force_change_attribute(:next_on, Date.add(date, weeks * 7))
    |> Ash.Changeset.after_action(fn _changeset, repeat ->
      latest = repeat |> Ash.load!([latest_order: :line_items], authorize?: false) |> Map.fetch!(:latest_order)

      Order
      |> Ash.Changeset.for_create(:place_custom, params(latest, repeat, date), actor: context.actor, authorize?: false)
      |> Ash.create!()

      {:ok, repeat}
    end)
  end

  # A job that didn't run for a while places from today on, never a past date.
  defp catch_up(date, weeks) do
    if Date.before?(date, Edenflowers.ShopTime.today()), do: catch_up(Date.add(date, weeks * 7), weeks), else: date
  end

  defp params(order, repeat, date) do
    {cards, items} = Enum.split_with(order.line_items, & &1.is_card)
    card = List.first(cards)

    order
    |> Map.take(~w(locale customer_name customer_email customer_phone_number customer_instagram gift recipient_name
         recipient_phone_number card_message fulfillment_option_id fulfillment_time_start fulfillment_time_end
         delivery_address delivery_instructions fulfillment_fee_override florist_note payment_terms)a)
    |> Map.merge(%{
      fulfillment_date: date,
      fulfillment_time: fulfillment_time(order),
      order_repeat_id: repeat.id,
      customer_id: order.user_id,
      card_variant_id: card && card.product_variant_id,
      email_customer?: false,
      line_items: Enum.map(items, &line/1)
    })
  end

  defp fulfillment_time(%{fulfillment_time_start: nil}), do: :any
  defp fulfillment_time(%{fulfillment_time_end: nil}), do: :at
  defp fulfillment_time(_order), do: :between

  defp line(%{product_variant_id: variant_id} = line) when not is_nil(variant_id) do
    %{kind: :catalogue, product_variant_id: variant_id, quantity: line.quantity, bow_colour: line.bow_colour}
  end

  defp line(line) do
    %{
      kind: :custom,
      product_name: line.product_name,
      unit_price: line.unit_price,
      quantity: line.quantity,
      tax_rate_id: tax_rate_id(line.tax_rate)
    }
  end

  # A line stores the percentage it was charged, not the rate it came from.
  defp tax_rate_id(percentage) do
    %{percentages: [percentage]}
    |> Edenflowers.Pricing.list_selectable_tax_rates!(authorize?: false)
    |> Enum.find_value(&(Decimal.equal?(&1.percentage, percentage) && &1.id))
  end
end
