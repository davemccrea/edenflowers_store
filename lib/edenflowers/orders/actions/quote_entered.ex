defmodule Edenflowers.Orders.Actions.QuoteEntered do
  @moduledoc """
  What an order Jennie is entering or editing will cost once saved, priced
  from the same params `:place_custom` and `:edit` take, so she can tell a
  customer on the phone before she places it.

  It builds that action's changeset without submitting it, so nothing is
  saved, while the action's own changes add the card line, snapshot the fee's
  VAT rate and say whether the fee is priced afresh. The lines, promotion and
  fee are then priced by the rules saving uses: `PopulateFromVariant`,
  `PriceFulfillment`, the `PromotionApplied` and `LineDiscount` expressions,
  the order's `fee_for_cart` and `Vat.compute_breakdown/1`. A delivery address
  is priced by the quote the form already looked up, so nothing is geocoded.

  A line that isn't filled in yet is left out. The fee is nil while it can't be
  priced, and the total then leaves it out.
  """
  use Ash.Resource.Actions.Implementation

  alias Edenflowers.Orders
  alias Edenflowers.Orders.Calculations.LineDiscount
  alias Edenflowers.Orders.Calculations.PromotionApplied
  alias Edenflowers.Orders.Calculations.Vat
  alias Edenflowers.Orders.Changes.PopulateFromVariant
  alias Edenflowers.Orders.Changes.PriceFulfillment
  alias Edenflowers.Orders.LineItem
  alias Edenflowers.Orders.Order

  @impl true
  def run(input, _opts, context) do
    order = input.arguments[:order]
    changeset = changeset(order, input.arguments.params, context.actor)
    {:ok, entered} = Ash.Changeset.apply_attributes(changeset, force?: true)

    lines = changeset |> entered_lines(order, entered.locale) |> apply_promotion(entered)
    free_delivery? = Enum.any?(lines, & &1.free_delivery)
    fee = fulfillment_fee(changeset, input.arguments[:delivery_quote], free_delivery?)

    vat_rows =
      Vat.compute_breakdown(%{
        line_items: lines,
        fulfillment_fee: fee,
        fulfillment_tax_rate: entered.fulfillment_tax_rate
      })

    {:ok,
     %{
       lines: Enum.map(lines, &%{name: &1.product_name, quantity: &1.quantity, total: &1.total}),
       fulfillment_fee: fee,
       free_delivery?: free_delivery?,
       vat: sum(vat_rows, :vat),
       total: Decimal.add(sum(lines, :total), fee || 0)
     }}
  end

  defp changeset(nil, params, actor), do: Ash.Changeset.for_create(Order, :place_custom, params, actor: actor)
  defp changeset(order, params, actor), do: Ash.Changeset.for_update(order, :edit, params, actor: actor)

  # The lines `manage_relationship` would save, the card among them.
  defp entered_lines(changeset, order, locale) do
    changeset
    |> Ash.Changeset.get_argument(:line_items)
    |> List.wrap()
    |> Enum.map(&entered_line(&1, order, locale))
    |> Enum.reject(&is_nil/1)
  end

  # A line the order has keeps the price it was sold at.
  defp entered_line(%{"id" => id} = params, order, _locale) when id not in [nil, ""] do
    case order && Enum.find(order.line_items, &(&1.id == id)) do
      nil -> nil
      line_item -> line_item |> Ash.Changeset.for_update(:set_quantity, Map.take(params, ["quantity"])) |> priced()
    end
  end

  defp entered_line(params, _order, locale) do
    changeset = Ash.Changeset.for_create(LineItem, :enter, Map.delete(params, "id"))

    if changeset.valid? and Ash.Changeset.get_argument(changeset, :kind) == :catalogue do
      case PopulateFromVariant.snapshot(Ash.Changeset.get_attribute(changeset, :product_variant_id), locale) do
        {:ok, attrs} -> changeset |> Ash.Changeset.force_change_attributes(attrs) |> priced()
        :error -> nil
      end
    else
      priced(changeset)
    end
  end

  defp priced(%{valid?: true} = changeset) do
    {:ok, line_item} = Ash.Changeset.apply_attributes(changeset)
    %{line_item | subtotal: Decimal.mult(line_item.unit_price, line_item.quantity)}
  end

  defp priced(_changeset), do: nil

  defp apply_promotion(lines, entered) do
    entered = %{entered | items_subtotal: sum(lines, :subtotal)}
    applied? = eval(PromotionApplied, entered, Order)

    Enum.map(lines, fn line ->
      line = %{line | order: entered, promotion_applied?: applied?}
      discount = eval(LineDiscount, line, LineItem)
      %{line | discount: discount, total: Decimal.sub(line.subtotal, discount)}
    end)
  end

  # The calculation's expression, evaluated on a record that isn't saved. It
  # raises on a field the record doesn't have, rather than reading it as nil.
  defp eval(calculation, record, resource) do
    calculation.expression([], %{})
    |> Ash.Expr.eval!(record: record, resource: resource, unknown_on_unknown_refs?: true)
  end

  defp fulfillment_fee(changeset, delivery_quote, free_delivery?) do
    case quoted_fee(changeset, delivery_quote) do
      %{quoted_fulfillment_fee: quoted, in_free_delivery_zone: in_zone} when not is_nil(quoted) ->
        override = Ash.Changeset.get_attribute(changeset, :fulfillment_fee_override)
        Orders.charged_fulfillment_fee!(quoted, in_zone, free_delivery?, override)

      _ ->
        nil
    end
  end

  defp quoted_fee(changeset, delivery_quote) do
    if PriceFulfillment.reprices?(changeset) do
      case PriceFulfillment.price(changeset, fn _address, _option -> located(delivery_quote) end) do
        {:ok, attributes} -> attributes
        {:error, _field, _message} -> nil
      end
    else
      Map.take(changeset.data, [:quoted_fulfillment_fee, :in_free_delivery_zone])
    end
  end

  # An address the form hasn't priced yet is priced as one that can't be.
  defp located(nil), do: {:error, :unknown}

  defp located(delivery_quote),
    do: {:ok, %{fulfillment_fee: delivery_quote.fee, in_free_delivery_zone: delivery_quote.in_free_delivery_zone}}

  defp sum(rows, key), do: Enum.reduce(rows, Decimal.new(0), &Decimal.add(Map.fetch!(&1, key), &2))
end
