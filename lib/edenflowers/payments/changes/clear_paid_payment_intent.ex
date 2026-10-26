defmodule Edenflowers.Payments.Changes.ClearPaidPaymentIntent do
  @moduledoc """
  Clears the record's PaymentIntent only if it's the one paid, given as the
  `payment_intent_id` argument. One Jennie dropped by recording a payment can
  still be paid, and that money has arrived all the same.
  """
  use Ash.Resource.Change
  require Ash.Expr

  @impl true
  def change(changeset, _opts, _context) do
    paid_id = Ash.Changeset.get_argument(changeset, :payment_intent_id)

    Ash.Changeset.atomic_update(
      changeset,
      :payment_intent_id,
      Ash.Expr.expr(if payment_intent_id == ^paid_id, do: nil, else: payment_intent_id)
    )
  end
end
