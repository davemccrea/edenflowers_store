defmodule Edenflowers.Orders.Changes.RepriceOrderFulfillment do
  @moduledoc """
  Reprices the cart's delivery after a product is added, as it may be the
  cart's first free-delivery product. Placed orders are skipped: Jennie's
  edits reprice once, after `ReplaceLineItems` has changed all the lines.
  """
  use Ash.Resource.Change

  alias Edenflowers.Orders

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, line_item ->
      order = Ash.get!(Orders.Order, line_item.order_id, authorize?: false)

      if order.state == :placed do
        {:ok, line_item}
      else
        with {:ok, _order} <- Orders.reprice_fulfillment(order, authorize?: false), do: {:ok, line_item}
      end
    end)
  end
end
