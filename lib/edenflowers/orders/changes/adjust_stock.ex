defmodule Edenflowers.Orders.Changes.AdjustStock do
  @moduledoc """
  Takes an order's tracked sizes off the shelf (`direction: :take`), or puts
  them back (`direction: :return`).

  Stock never goes below 0. Nothing here is ever refused: an Online Order has
  been paid for by the time it is placed, and Jennie knows the shelf better
  than the count does. With `report_oversell?: true`, taking more than is left
  is logged as an error so it reaches ErrorTracker.
  """
  use Ash.Resource.Change

  require Ash.Query
  require Logger

  alias Edenflowers.Catalog.ProductVariant

  @impl true
  def init(opts) do
    if opts[:direction] in [:take, :return],
      do: {:ok, opts},
      else: {:error, "direction must be :take or :return"}
  end

  # Returned before the write, as an edit saves the lines replacing these with it.
  @impl true
  def change(changeset, opts, _context) do
    case opts[:direction] do
      :return ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          case adjust_order(changeset.data, opts) do
            :ok -> changeset
            {:error, error} -> Ash.Changeset.add_error(changeset, error)
          end
        end)

      :take ->
        Ash.Changeset.after_action(changeset, fn _changeset, order ->
          with :ok <- adjust_order(order, opts), do: {:ok, order}
        end)
    end
  end

  # Occurrences are made fresh and never take stock, so they have none to return.
  defp adjust_order(%{origin: :subscription}, _opts), do: :ok

  defp adjust_order(order, opts) do
    with {:ok, %{line_items: line_items}} <- Ash.load(order, :line_items, authorize?: false) do
      adjust_all(order, line_items, opts)
    end
  end

  # Sorted so two orders sharing sizes lock them in the same order and can't
  # deadlock.
  defp adjust_all(order, line_items, opts) do
    line_items
    |> quantities_by_variant()
    |> Enum.sort()
    |> Enum.reduce_while(:ok, fn {variant_id, quantity}, :ok ->
      case adjust(order, variant_id, quantity, opts) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp quantities_by_variant(line_items) do
    line_items
    |> Enum.reject(&is_nil(&1.product_variant_id))
    # A subscription's bouquets are made fresh, its first one included.
    |> Enum.filter(&is_nil(&1.interval_weeks))
    |> Enum.group_by(& &1.product_variant_id, & &1.quantity)
    |> Map.new(fn {variant_id, quantities} -> {variant_id, Enum.sum(quantities)} end)
  end

  # adjust_stock alone is safe. The lock is only so the oversell report reads
  # the count the update will act on.
  defp adjust(order, variant_id, quantity, opts) do
    ProductVariant
    |> Ash.Query.filter(id == ^variant_id and not is_nil(stock_quantity))
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        :ok

      {:ok, variant} ->
        if Keyword.get(opts, :report_oversell?, false) and quantity > variant.stock_quantity do
          Logger.error(
            "Order #{order.id} took #{quantity} of variant #{variant.id} with only " <>
              "#{variant.stock_quantity} in stock."
          )
        end

        by = if opts[:direction] == :take, do: -quantity, else: quantity

        with {:ok, _variant} <- Ash.update(variant, %{by: by}, action: :adjust_stock, authorize?: false), do: :ok

      {:error, error} ->
        {:error, error}
    end
  end
end
