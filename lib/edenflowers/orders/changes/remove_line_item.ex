defmodule Edenflowers.Orders.Changes.RemoveLineItem do
  @moduledoc """
  Destroys a line item belonging to the order. If removing it leaves the
  order with no non-card line items, the order's checkout state is also
  reset so a new browsing session starts from a clean slate.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Edenflowers.Orders.LineItem

  alias Edenflowers.Orders

  @impl true
  def change(changeset, _opts, _context) do
    line_item_id = Ash.Changeset.get_argument(changeset, :line_item_id)

    Ash.Changeset.after_action(changeset, fn _changeset, order ->
      with {:ok, line_item} <- fetch_line_item(line_item_id, order.id),
           :ok <- Ash.destroy(line_item, action: :remove_item, authorize?: false) do
        maybe_restart_checkout(order)
      end
    end)
  end

  defp fetch_line_item(line_item_id, order_id) do
    line_item =
      LineItem
      |> Ash.Query.filter(id == ^line_item_id and order_id == ^order_id)
      |> Ash.read_one(authorize?: false)

    case line_item do
      {:ok, nil} -> {:error, :line_item_not_found}
      result -> result
    end
  end

  defp maybe_restart_checkout(order) do
    order = Ash.load!(order, :non_card_line_item_count, authorize?: false)

    if order.non_card_line_item_count == 0 do
      Orders.restart_checkout(order, authorize?: false)
    else
      {:ok, order}
    end
  end
end
