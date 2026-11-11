defmodule Edenflowers.Payments.Validations.Payable do
  @moduledoc "Refuses a new PaymentIntent for an order or booking that owes nothing."
  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidAttribute

  @impl true
  def atomic(_changeset, _opts, _context) do
    # Before it's placed or confirmed there's no Balance yet (ADR 0007), only what checkout charges.
    {:atomic, [:payment_intent_id], expr(if committed?, do: not payable?, else: checkout_total <= 0),
     expr(error(^InvalidAttribute, %{field: :payment_intent_id, value: payment_intent_id, message: "is not payable"}))}
  end
end
