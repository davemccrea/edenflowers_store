defmodule Edenflowers.Store.Order.Changes.SnapshotTotals do
  @moduledoc """
  Runs in `before_action` on `:finalize_checkout`, while the order is still
  in `:payment`, and freezes the cart's live aggregates and the promotion
  code into the order's and line items' `placed_*` columns.

  After this runs, a placed order's numbers no longer depend on upstream
  rows (promotion percentage, tax rate, fulfillment option) so an admin
  edit to any of those rows can't rewrite history. See ADR 0001.
  """
  use Ash.Resource.Change

  import Edenflowers.Actors

  alias Edenflowers.Store.LineItem

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &snapshot/1)
  end

  defp snapshot(changeset) do
    order =
      changeset.data
      |> Ash.load!(
        [
          :line_total,
          :line_tax_amount,
          :discount_amount,
          :fulfillment_tax_amount,
          :tax_amount,
          :total,
          :promotion,
          line_items: [:line_total, :discount_amount, :line_tax_amount]
        ],
        authorize?: false
      )

    snapshot_line_items(order.line_items)

    Ash.Changeset.force_change_attributes(changeset,
      placed_line_total: order.line_total,
      placed_line_tax_amount: order.line_tax_amount,
      placed_discount_amount: order.discount_amount,
      placed_fulfillment_tax_amount: order.fulfillment_tax_amount,
      placed_tax_amount: order.tax_amount,
      placed_total: order.total,
      placed_promotion_code: order.promotion && order.promotion.code
    )
  end

  defp snapshot_line_items(line_items) do
    Enum.each(line_items, fn item ->
      item
      |> Ash.Changeset.for_update(
        :snapshot_totals,
        %{
          placed_line_total: item.line_total,
          placed_discount_amount: item.discount_amount,
          placed_line_tax_amount: item.line_tax_amount
        },
        actor: system_actor()
      )
      |> Ash.update!()
    end)
  end
end
