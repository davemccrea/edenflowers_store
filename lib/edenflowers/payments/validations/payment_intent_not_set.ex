defmodule Edenflowers.Payments.Validations.PaymentIntentNotSet do
  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidAttribute

  @impl true
  def atomic(_changeset, _opts, _context) do
    {:atomic, [:payment_intent_id], expr(not is_nil(payment_intent_id)),
     expr(
       error(^InvalidAttribute, %{
         field: :payment_intent_id,
         value: payment_intent_id,
         message: "has already been set"
       })
     )}
  end
end
