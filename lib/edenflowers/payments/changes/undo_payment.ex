defmodule Edenflowers.Payments.Changes.UndoPayment do
  @moduledoc """
  Sets up `undo_payment` to record the opposite of the `payment_id` payment,
  by the same method. Refused unless the payment is the record's, wasn't
  through checkout, isn't itself an undo and hasn't been undone.

  Undoing a Stripe app payment unlinks it: refused while Stripe has refunds on
  it, it marks the payment unlinked so its PaymentIntent can be linked again,
  and once committed takes this purchase out of the PaymentIntent's metadata.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "admin"]

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Payments
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
      |> unlink(payment)
    else
      _ -> Ash.Changeset.add_error(changeset, field: :payment_id, message: "can't be undone")
    end
  end

  defp unlink(changeset, %Payment{stripe_app: false}), do: changeset

  defp unlink(changeset, payment) do
    changeset
    |> Ash.Changeset.before_transaction(&refuse_if_refunded(&1, payment))
    |> Ash.Changeset.after_action(fn _changeset, record ->
      with {:ok, _payment} <- Ash.update(payment, %{}, action: :unlink, authorize?: false),
           do: {:ok, record}
    end)
    |> Ash.Changeset.after_transaction(fn
      _changeset, {:ok, record} ->
        Payments.write_stripe_app_link(payment.payment_intent_id, payment |> payable_key() |> to_string(), nil)
        {:ok, record}

      _changeset, error ->
        error
    end)
  end

  # Unlinking money Stripe has since handed back would leave its refund on
  # the wrong purchase.
  defp refuse_if_refunded(changeset, payment) do
    case StripeAPI.impl().list_refunds(payment.payment_intent_id) do
      {:ok, refunds} ->
        if Enum.any?(refunds, &(&1.status not in ["failed", "canceled"])),
          do:
            Ash.Changeset.add_error(changeset,
              field: :payment_id,
              message: ~t"It has refunds, so it can't be unlinked."
            ),
          else: changeset

      {:error, _reason} ->
        Ash.Changeset.add_error(changeset,
          field: :payment_id,
          message: ~t"Could not reach Stripe. Try again in a moment."
        )
    end
  end

  defp payable_key(%Payment{order_id: nil}), do: :course_registration_id
  defp payable_key(%Payment{}), do: :order_id
end
