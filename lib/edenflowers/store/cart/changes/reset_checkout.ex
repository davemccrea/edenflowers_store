defmodule Edenflowers.Store.Cart.Changes.ResetCheckout do
  @moduledoc """
  Returns a cart to its initial checkout state: blanks every checkout
  field and destroys any line items left on the cart. The cart row, its
  id, `order_reference`, and `state` are preserved so the existing browser
  session keeps pointing at the same cart.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Edenflowers.Store.CartLineItem

  @reset_attrs %{
    customer_name: nil,
    customer_email: nil,
    gift: false,
    recipient_name: nil,
    card_message: nil,
    recipient_phone_number: nil,
    delivery_address: nil,
    delivery_instructions: nil,
    fulfillment_date: nil,
    fulfillment_amount: nil,
    geocoded_address: nil,
    here_id: nil,
    distance: nil,
    position: nil,
    payment_intent_id: nil,
    promotion_id: nil,
    fulfillment_option_id: nil
  }

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.force_change_attributes(@reset_attrs)
    |> Ash.Changeset.after_action(&destroy_line_items/2)
  end

  defp destroy_line_items(_changeset, cart) do
    CartLineItem
    |> Ash.Query.filter(cart_id == ^cart.id)
    |> Ash.read!(authorize?: false)
    |> Enum.reduce_while(:ok, fn line_item, :ok ->
      case Ash.destroy(line_item, action: :remove_item, authorize?: false) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      :ok -> {:ok, cart}
      {:error, error} -> {:error, error}
    end
  end
end
