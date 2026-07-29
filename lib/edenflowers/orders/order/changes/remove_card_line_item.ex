defmodule Edenflowers.Orders.Order.Changes.RemoveCardLineItem do
  @moduledoc """
  Destroys the card line item on the order, if any. The order's
  `card_message` is cleared by the parent action's `set_attribute` change;
  this module only handles the line-item side of the operation.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Edenflowers.Orders.LineItem

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, order ->
      LineItem
      |> Ash.Query.filter(order_id == ^order.id and is_card == true)
      |> Ash.read_one(authorize?: false)
      |> case do
        {:ok, nil} ->
          {:ok, order}

        {:ok, line_item} ->
          case Ash.destroy(line_item, action: :remove_item, authorize?: false) do
            :ok -> {:ok, order}
            {:error, error} -> {:error, error}
          end

        {:error, error} ->
          {:error, error}
      end
    end)
  end
end
