defmodule Edenflowers.Orders.Order.Changes.SwapCardLineItem do
  @moduledoc """
  Replaces the card line item on the order with one created from the given
  `product_variant_id` argument. Any existing card line item is destroyed
  first, in the same transaction as the new line item is created, so the
  "one card per order" invariant is preserved across concurrent requests.
  """
  use Ash.Resource.Change

  alias Edenflowers.Orders.LineItem
  alias Edenflowers.Orders.Order.Changes.RemoveCardLineItem

  @impl true
  def change(changeset, _opts, _context) do
    product_variant_id = Ash.Changeset.get_argument(changeset, :product_variant_id)

    Ash.Changeset.after_action(changeset, fn _changeset, order ->
      with :ok <- RemoveCardLineItem.destroy_card(order.id),
           {:ok, _line_item} <- create_card(order.id, product_variant_id) do
        {:ok, order}
      end
    end)
  end

  defp create_card(order_id, product_variant_id) do
    LineItem
    |> Ash.Changeset.for_create(:add_to_cart, %{
      order_id: order_id,
      product_variant_id: product_variant_id,
      quantity: 1,
      is_card: true
    })
    |> Ash.create(authorize?: false)
  end
end
