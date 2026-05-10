defmodule Edenflowers.Store.Order.Changes.SnapshotTotals do
  @moduledoc """
  At `:finalize_checkout`, captures all derived numeric values from the cart
  into stored `placed_*` attributes on the order, and into `placed_*`
  attributes on each line item.

  After this runs and the order transitions to `:placed`:

    * Lockdown policies refuse any further mutation of either resource.
    * Reads on placed orders take their numbers from `placed_*` fields,
      not from live aggregates/calculations — so a later edit to
      `promotion.discount_percentage`, `tax_rate.percentage` or
      `fulfillment_option.base_price` cannot retroactively change what
      this order says.

  Runs in `before_action`. The order is still in `:payment` state at this
  point, which is what the cart-flow load and the `:update` policies
  expect; the state transition to `:placed` happens later in the same
  action via `transition_state(:placed)`.

  Snapshots:

    * `placed_line_total`, `placed_line_tax_amount`,
      `placed_discount_amount` — were aggregates over `line_items`;
      copied as concrete decimals.
    * `placed_fulfillment_tax_amount` — was a calculation deriving from
      `fulfillment_amount * fulfillment_option.tax_rate.percentage`;
      copied as a concrete decimal. The rate itself is already
      denormalised to `fulfillment_tax_rate` at submit_delivery, but the
      *amount* is what the receipt prints.
    * `placed_tax_amount`, `placed_total` — derived totals; concrete
      decimals.
    * `placed_promotion_code` — was read live via `order.promotion.code`;
      a later admin edit of the promotion's code must not change what
      this order's confirmation email/receipt displays.
    * Per line item: `placed_line_total`, `placed_discount_amount`,
      `placed_line_tax_amount` — were calculations on LineItem that
      depended on the live promotion percentage. Concrete decimals after.
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
