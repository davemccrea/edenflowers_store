defmodule Edenflowers.Orders.Order.Changes.ResetCheckout do
  @moduledoc """
  Returns an order to its initial checkout state: blanks every checkout
  field and destroys any line items left on the order. The order row, its
  id, `order_reference`, and `state` are preserved so the existing browser
  session keeps pointing at the same cart.

  An order with a PaymentIntent may be paid after the reset, so it keeps the
  PaymentIntent and who is paying: the order is still placed, and its
  confirmation email still has somewhere to go.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Edenflowers.Orders.LineItem
  alias Edenflowers.Orders.Order.Changes.ClearDeliveryFields
  alias Edenflowers.Orders.Order.Changes.ClearPromotionFields

  @reset_attrs Map.from_keys(ClearDeliveryFields.fields() ++ ClearPromotionFields.fields(), nil)
               |> Map.merge(%{
                 customer_name: nil,
                 customer_email: nil,
                 customer_phone_number: nil,
                 user_id: nil,
                 gift: false,
                 recipient_name: nil,
                 card_message: nil,
                 recipient_phone_number: nil,
                 fulfillment_date: nil,
                 fulfillment_option_id: nil,
                 fulfillment_method: nil,
                 fulfillment_tax_rate: nil,
                 fulfillment_option_name: nil
               })

  @impl true
  def change(changeset, _opts, _context) do
    reset_attrs =
      if changeset.data.payment_intent_id do
        Map.drop(@reset_attrs, [:customer_name, :customer_email, :customer_phone_number, :user_id])
      else
        @reset_attrs
      end

    changeset
    |> Ash.Changeset.force_change_attributes(reset_attrs)
    |> Ash.Changeset.after_action(&destroy_line_items/2)
  end

  defp destroy_line_items(_changeset, order) do
    result =
      LineItem
      |> Ash.Query.filter(order_id == ^order.id)
      |> Ash.bulk_destroy(:remove_item, %{},
        strategy: [:atomic, :stream],
        notify?: true,
        return_errors?: true,
        authorize?: false
      )

    case result do
      %Ash.BulkResult{status: :success} -> {:ok, order}
      %Ash.BulkResult{errors: errors} -> {:error, errors}
    end
  end
end
