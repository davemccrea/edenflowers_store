defmodule Edenflowers.Payments.Validations.MatchesPaymentIntent do
  @moduledoc """
  Fails with `PaymentIntentMismatch` unless the `payment_intent_id` argument
  is the PaymentIntent stored on the record.
  """
  use Ash.Resource.Validation

  alias Edenflowers.Payments.Errors.PaymentIntentMismatch

  @impl true
  def atomic(changeset, _opts, _context) do
    actual = Ash.Changeset.get_argument(changeset, :payment_intent_id)

    # A nil argument is already rejected by allow_nil? false.
    if is_nil(actual) do
      :ok
    else
      {:atomic, :*, expr(is_nil(payment_intent_id) or payment_intent_id != ^actual),
       expr(error(^PaymentIntentMismatch, %{expected: payment_intent_id, actual: ^actual}))}
    end
  end
end
