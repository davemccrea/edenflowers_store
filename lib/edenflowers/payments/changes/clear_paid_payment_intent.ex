defmodule Edenflowers.Payments.Changes.ClearPaidPaymentIntent do
  @moduledoc """
  Clears the record's PaymentIntent only if it's the one paid, given as the
  `payment_intent_id` argument. One Jennie dropped by recording a payment can
  still be paid, and that money has arrived all the same.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    if changeset.data.payment_intent_id == Ash.Changeset.get_argument(changeset, :payment_intent_id),
      do: Ash.Changeset.force_change_attribute(changeset, :payment_intent_id, nil),
      else: changeset
  end
end
