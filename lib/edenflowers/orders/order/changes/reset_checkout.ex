defmodule Edenflowers.Orders.Order.Changes.ResetCheckout do
  @moduledoc """
  Returns an order to its initial checkout state: blanks every checkout
  field and destroys any line items left on the order. The order row, its
  id, `order_reference`, and `state` are preserved so the existing browser
  session keeps pointing at the same cart.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Edenflowers.Orders.LineItem

  @reset_attrs %{
    customer_name: nil,
    customer_email: nil,
    newsletter_offer_hidden?: false,
    gift: false,
    recipient_name: nil,
    card_message: nil,
    recipient_phone_number: nil,
    delivery_address: nil,
    delivery_instructions: nil,
    fulfillment_date: nil,
    fulfillment_fee: nil,
    geocoded_address: nil,
    here_id: nil,
    distance: nil,
    position: nil,
    payment_intent_id: nil,
    promotion_id: nil,
    discount_rate: nil,
    promotion_name: nil,
    promotion_code: nil,
    promotion_minimum_cart_total: nil,
    fulfillment_option_id: nil
  }

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.force_change_attributes(@reset_attrs)
    |> Ash.Changeset.after_action(&destroy_line_items/2)
  end

  defp destroy_line_items(_changeset, order) do
    LineItem
    |> Ash.Query.filter(order_id == ^order.id)
    |> Ash.bulk_destroy(:remove_item, %{},
      strategy: [:atomic, :stream],
      notify?: true,
      return_errors?: true,
      authorize?: false
    )
    |> case do
      %Ash.BulkResult{status: :success} -> {:ok, order}
      %Ash.BulkResult{errors: errors} -> {:error, errors}
    end
  end
end
