defmodule Edenflowers.Store.Order.Changes.SnapshotTotals do
  @moduledoc """
  Captures the cart's derived numeric values into `placed_*` attributes
  on the order and its line items at `:finalize_checkout`. See ADR-0001.
  """
  use Ash.Resource.Change

  import Edenflowers.Actors

  @order_aggregates_and_calcs [
    :line_total,
    :line_tax_amount,
    :discount_amount,
    :fulfillment_tax_amount,
    :tax_amount,
    :total,
    :promotion,
    :line_items
  ]

  @line_item_calcs [
    :line_total,
    :discount_amount,
    :line_tax_amount
  ]

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &snapshot/1)
  end

  defp snapshot(changeset) do
    order =
      Ash.load!(
        changeset.data,
        @order_aggregates_and_calcs,
        authorize?: false,
        lazy?: true
      )

    changeset =
      Ash.Changeset.force_change_attributes(changeset, %{
        placed_line_total: zero_if_nil(order.line_total),
        placed_line_tax_amount: zero_if_nil(order.line_tax_amount),
        placed_discount_amount: zero_if_nil(order.discount_amount),
        placed_fulfillment_tax_amount: zero_if_nil(order.fulfillment_tax_amount),
        placed_tax_amount: zero_if_nil(order.tax_amount),
        placed_total: zero_if_nil(order.total),
        placed_promotion_code: promotion_code(order)
      })

    Ash.Changeset.after_action(changeset, fn _changeset, persisted_order ->
      snapshot_line_items(persisted_order)
    end)
  end

  defp snapshot_line_items(order) do
    order.line_items
    |> Enum.reduce_while({:ok, order}, fn item, {:ok, _} = acc ->
      loaded = Ash.load!(item, @line_item_calcs, authorize?: false, lazy?: true)

      attrs = %{
        placed_line_total: zero_if_nil(loaded.line_total),
        placed_discount_amount: zero_if_nil(loaded.discount_amount),
        placed_line_tax_amount: zero_if_nil(loaded.line_tax_amount)
      }

      case loaded
           |> Ash.Changeset.for_update(:snapshot_totals, attrs)
           |> Ash.update(actor: system_actor()) do
        {:ok, _updated} -> {:cont, acc}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp promotion_code(%{promotion: %{code: code}}) when is_binary(code), do: code
  defp promotion_code(_), do: nil

  defp zero_if_nil(nil), do: Decimal.new(0)
  defp zero_if_nil(value), do: value
end
