defmodule Edenflowers.Store.Order.ValidatePaymentIntent do
  @moduledoc """
  Validates that a payment_intent_id is present before finalizing checkout.

  This ensures an order cannot be finalized without a valid Stripe payment intent.
  """
  use Ash.Resource.Change
  use Gettext, backend: EdenflowersWeb.Gettext

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    payment_intent_id = Ash.Changeset.get_attribute(changeset, :payment_intent_id)

    if is_nil(payment_intent_id) or payment_intent_id == "" do
      Ash.Changeset.add_error(changeset, %Ash.Error.Changes.Required{
        field: :payment_intent_id,
        type: :attribute
      })
    else
      changeset
    end
  end
end
