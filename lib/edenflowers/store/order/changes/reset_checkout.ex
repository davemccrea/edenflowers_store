defmodule Edenflowers.Store.Order.Changes.ResetCheckout do
  use Ash.Resource.Change

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.force_change_attributes(changeset, %{
      step: 1,
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
      calculated_address: nil,
      here_id: nil,
      distance: nil,
      position: nil,
      payment_intent_id: nil,
      promotion_id: nil,
      fulfillment_option_id: nil
    })
  end
end
