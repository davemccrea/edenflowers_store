defmodule Edenflowers.Store.Order.Validations.ValidatePaymentIntent do
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @impl true
  def validate(changeset, _opts, _context) do
    payment_intent_id = Ash.Changeset.get_attribute(changeset, :payment_intent_id)

    if is_nil(payment_intent_id) or payment_intent_id == "" do
      {:error, field: :payment_intent_id, message: ~t"Payment intent is required"}
    else
      :ok
    end
  end
end
