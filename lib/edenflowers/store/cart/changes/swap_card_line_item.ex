defmodule Edenflowers.Store.Cart.Changes.SwapCardLineItem do
  @moduledoc """
  Replaces the card line item on the cart with one created from the given
  `product_variant_id` argument. Any existing card line item is destroyed
  first, in the same transaction as the new line item is created, so the
  "one card per cart" invariant is preserved across concurrent requests.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Edenflowers.Store.CartLineItem

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, cart ->
      product_variant_id = Ash.Changeset.get_argument(changeset, :product_variant_id)

      with :ok <- destroy_existing_card(cart.id),
           {:ok, _line_item} <- create_card(cart.id, product_variant_id) do
        {:ok, cart}
      end
    end)
  end

  defp destroy_existing_card(cart_id) do
    CartLineItem
    |> Ash.Query.filter(cart_id == ^cart_id and is_card == true)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> :ok
      {:ok, line_item} -> Ash.destroy(line_item, action: :remove_item, authorize?: false)
      {:error, error} -> {:error, error}
    end
  end

  defp create_card(cart_id, product_variant_id) do
    CartLineItem
    |> Ash.Changeset.for_create(:add_to_cart, %{
      cart_id: cart_id,
      product_variant_id: product_variant_id,
      quantity: 1,
      is_card: true
    })
    |> Ash.create(authorize?: false)
  end
end
