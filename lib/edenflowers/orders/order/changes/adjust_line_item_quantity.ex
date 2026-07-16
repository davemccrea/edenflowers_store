defmodule Edenflowers.Orders.Order.Changes.AdjustLineItemQuantity do
  @moduledoc """
  Increments or decrements the quantity of a line item belonging to the
  order. The action argument `:direction` chooses between `:increment` and
  `:decrement`, both of which delegate to LineItem's matching update action.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Edenflowers.Orders.LineItem

  @impl true
  def init(opts) do
    case Keyword.fetch(opts, :direction) do
      {:ok, direction} when direction in [:increment, :decrement] -> {:ok, opts}
      _ -> {:error, "expected :direction to be :increment or :decrement"}
    end
  end

  @impl true
  def change(changeset, opts, _context) do
    line_item_id = Ash.Changeset.get_argument(changeset, :line_item_id)
    direction = Keyword.fetch!(opts, :direction)

    Ash.Changeset.after_action(changeset, fn _changeset, order ->
      with {:ok, line_item} <- fetch_line_item(line_item_id, order.id),
           {:ok, _line_item} <- adjust(line_item, direction) do
        {:ok, order}
      end
    end)
  end

  defp fetch_line_item(line_item_id, order_id) do
    LineItem
    |> Ash.Query.filter(id == ^line_item_id and order_id == ^order_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :line_item_not_found}
      {:ok, line_item} -> {:ok, line_item}
      {:error, error} -> {:error, error}
    end
  end

  defp adjust(line_item, :increment) do
    line_item
    |> Ash.Changeset.for_update(:increment_quantity)
    |> Ash.update(authorize?: false)
  end

  defp adjust(line_item, :decrement) do
    line_item
    |> Ash.Changeset.for_update(:decrement_quantity)
    |> Ash.update(authorize?: false)
  end
end
