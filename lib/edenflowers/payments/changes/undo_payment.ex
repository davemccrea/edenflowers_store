defmodule Edenflowers.Payments.Changes.UndoPayment do
  @moduledoc """
  Sets up `undo_payment` to record the opposite of the `payment_id` payment,
  by the same method. Refused unless the payment is the record's, wasn't
  through Stripe, isn't itself an undo and hasn't been undone.
  """
  use Ash.Resource.Change

  alias Edenflowers.Payments.Payment

  @impl true
  def change(changeset, _opts, _context) do
    payment_id = Ash.Changeset.get_argument(changeset, :payment_id)

    with {:ok, payment} <- Ash.get(Payment, payment_id, load: [:undoable?], authorize?: false),
         true <- payment.undoable?,
         true <- changeset.data.id in [payment.order_id, payment.course_registration_id] do
      changeset
      |> Ash.Changeset.set_argument(:amount, Decimal.negate(payment.amount))
      |> Ash.Changeset.set_argument(:payment_method, payment.method)
      |> Ash.Changeset.set_argument(:reverses_payment_id, payment.id)
      |> Ash.Changeset.set_argument(:goodwill, payment.goodwill)
    else
      _ -> Ash.Changeset.add_error(changeset, field: :payment_id, message: "can't be undone")
    end
  end
end
