defmodule Edenflowers.Orders.Order.Changes.SwapCardLineItem do
  @moduledoc """
  Replaces the card line item on the order with one created from the given
  `product_variant_id` argument. Any existing card line item is destroyed
  first, in the same transaction as the new line item is created, so the
  "one card per order" invariant is preserved across concurrent requests.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Edenflowers.Orders.LineItem

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, order ->
      product_variant_id = Ash.Changeset.get_argument(changeset, :product_variant_id)

      with :ok <- destroy_existing_card(order.id),
           {:ok, _line_item} <- create_card(order.id, product_variant_id) do
        {:ok, order}
      end
    end)
  end

  defp destroy_existing_card(order_id) do
    LineItem
    |> Ash.Query.filter(order_id == ^order_id and is_card == true)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> :ok
      {:ok, line_item} -> Ash.destroy(line_item, action: :remove_item, authorize?: false)
      {:error, error} -> {:error, error}
    end
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
