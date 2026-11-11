defmodule Edenflowers.Orders.LineItem.Changes.RefreshPlacedOrder do
  @moduledoc """
  Keeps a placed order's stored grand total and VAT breakdown true to its
  lines whenever one is added, changed or removed, whichever action does it
  (ADR 0007). A cart stores neither, so its lines change nothing here.
  """
  use Ash.Resource.Change

  alias Edenflowers.Orders

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, line_item ->
      with {:ok, order} <- Orders.get_order_by_id(line_item.order_id, authorize?: false),
           {:ok, _order} <- refresh(order) do
        {:ok, line_item}
      end
    end)
  end

  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}

  defp refresh(%{state: :placed} = order), do: Orders.refresh_vat_breakdown(order, authorize?: false)
  defp refresh(order), do: {:ok, order}
end
