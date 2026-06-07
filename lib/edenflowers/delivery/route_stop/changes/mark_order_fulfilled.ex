defmodule Edenflowers.Delivery.RouteStop.Changes.MarkOrderFulfilled do
  @moduledoc """
  After a stop is delivered, mark its order fulfilled via the order's existing bypass.

  Idempotent: an already-fulfilled order is left untouched, so re-recording a delivered
  outcome (or retrying a stop) never fails on the order side.
  """
  use Ash.Resource.Change

  alias Edenflowers.Store.Order

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, stop ->
      with {:ok, order} <- Order.get_by_id(stop.order_id, authorize?: false),
           :pending <- order.fulfillment_status,
           {:ok, _order} <- Order.mark_fulfilled(order, authorize?: false) do
        {:ok, stop}
      else
        {:error, error} -> {:error, error}
        _ -> {:ok, stop}
      end
    end)
  end
end
