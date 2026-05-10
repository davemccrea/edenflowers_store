defmodule Edenflowers.Store.Cart.Changes.RemoveCardLineItem do
  @moduledoc """
  Destroys the card line item on the cart, if any. The cart's
  `card_message` is cleared by the parent action's `set_attribute` change;
  this module only handles the line-item side of the operation.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Edenflowers.Store.CartLineItem

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, cart ->
      CartLineItem
      |> Ash.Query.filter(cart_id == ^cart.id and is_card == true)
      |> Ash.read_one(authorize?: false)
      |> case do
        {:ok, nil} ->
          {:ok, cart}

        {:ok, line_item} ->
          case Ash.destroy(line_item, action: :remove_item, authorize?: false) do
            :ok -> {:ok, cart}
            {:error, error} -> {:error, error}
          end

        {:error, error} ->
          {:error, error}
      end
    end)
  end
end
