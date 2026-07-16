defmodule Edenflowers.Orders.Order.Changes.AddLineItem do
  @moduledoc """
  Adds a line item to the order via LineItem's `:add_to_cart` upsert. The
  Order-side action is the public seam for adding items so cart-mutation
  rules stay near the aggregate root; this change wires the create through.
  """
  use Ash.Resource.Change

  alias Edenflowers.Orders.LineItem

  @impl true
  def change(changeset, _opts, _context) do
    product_variant_id = Ash.Changeset.get_argument(changeset, :product_variant_id)
    quantity = Ash.Changeset.get_argument(changeset, :quantity)

    Ash.Changeset.after_action(changeset, fn _changeset, order ->
      LineItem
      |> Ash.Changeset.for_create(:add_to_cart, %{
        order_id: order.id,
        product_variant_id: product_variant_id,
        quantity: quantity
      })
      |> Ash.create(authorize?: false)
      |> case do
        {:ok, _line_item} -> {:ok, order}
        {:error, error} -> {:error, error}
      end
    end)
  end
end
