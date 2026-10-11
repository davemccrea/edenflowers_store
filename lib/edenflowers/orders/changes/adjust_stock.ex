defmodule Edenflowers.Orders.Changes.AdjustStock do
  @moduledoc """
  Takes an order's tracked sizes off the shelf when it is placed.

  Stock never goes below 0. An Online Order that takes more than is left has
  already been paid for, so it is placed all the same and the oversell is
  logged as an error so it reaches ErrorTracker.
  """
  use Ash.Resource.Change

  require Ash.Query
  require Logger

  alias Edenflowers.Catalog.ProductVariant

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, order ->
      order = Ash.load!(order, :line_items, authorize?: false)

      # Sorted so two orders sharing sizes lock them in the same order and
      # can't deadlock.
      for {variant_id, quantity} <- quantities_by_variant(order.line_items) |> Enum.sort() do
        take(order, variant_id, quantity)
      end

      {:ok, order}
    end)
  end

  defp quantities_by_variant(line_items) do
    line_items
    |> Enum.reject(&is_nil(&1.product_variant_id))
    |> Enum.group_by(& &1.product_variant_id, & &1.quantity)
    |> Map.new(fn {variant_id, quantities} -> {variant_id, Enum.sum(quantities)} end)
  end

  defp take(order, variant_id, quantity) do
    variant =
      ProductVariant
      |> Ash.Query.filter(id == ^variant_id and not is_nil(stock_quantity))
      |> Ash.Query.lock(:for_update)
      |> Ash.read_one!(authorize?: false)

    if variant do
      if quantity > variant.stock_quantity do
        Logger.error(
          "Order #{order.id} took #{quantity} of variant #{variant.id} with only " <>
            "#{variant.stock_quantity} in stock."
        )
      end

      variant
      |> Ash.Changeset.for_update(:update, %{stock_quantity: max(variant.stock_quantity - quantity, 0)})
      |> Ash.update!(authorize?: false)
    end
  end
end
