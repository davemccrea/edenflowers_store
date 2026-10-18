defmodule Edenflowers.Payments.Validations.Payable do
  @moduledoc "Refuses a new PaymentIntent for an order or booking that owes nothing."
  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidAttribute

  @impl true
  def atomic(_changeset, _opts, _context) do
    {:atomic, [:payment_intent_id], expr(not payable?),
     expr(error(^InvalidAttribute, %{field: :payment_intent_id, value: payment_intent_id, message: "is not payable"}))}
  end
end
