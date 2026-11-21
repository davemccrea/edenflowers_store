defmodule Edenflowers.Payments.Changes.LinkStripeAppPayment do
  @moduledoc """
  Sets up `link_stripe_payment` from the PaymentIntent Jennie picked: before
  the transaction, checks with Stripe that it's a Stripe app payment no
  purchase has yet, and sets the `amount` and `paid_with` that
  `RecordPayment` records. Once committed, writes the purchase into the
  PaymentIntent's metadata, so a refund made in Stripe finds it.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "admin"]

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Payments

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.before_transaction(&from_stripe/1)
    |> Ash.Changeset.after_transaction(fn
      changeset, {:ok, record} ->
        payment_intent_id = Ash.Changeset.get_argument(changeset, :payment_intent_id)
        Payments.write_stripe_app_link(payment_intent_id, metadata_key(record), record.id)
        {:ok, record}

      _changeset, error ->
        error
    end)
  end

  defp from_stripe(changeset) do
    payment_intent_id = Ash.Changeset.get_argument(changeset, :payment_intent_id)

    with {:ok, payment_intent} <- StripeAPI.impl().retrieve_payment_intent(%{payment_intent_id: payment_intent_id}),
         true <- Payments.stripe_app_payment?(payment_intent) and not Payments.recorded?(payment_intent_id) do
      # Known only now, from Stripe; Recordable checks the amount before the action.
      changeset
      |> Ash.Changeset.force_set_argument(:amount, StripeAPI.from_stripe_amount(payment_intent.amount_received))
      |> Ash.Changeset.force_set_argument(:paid_with, Payments.paid_with(payment_intent))
    else
      false ->
        Ash.Changeset.add_error(changeset,
          field: :payment_intent_id,
          message: ~t"That Stripe payment is already linked or didn't go through."
        )

      {:error, _reason} ->
        Ash.Changeset.add_error(changeset,
          field: :payment_intent_id,
          message: ~t"Could not reach Stripe. Try again in a moment."
        )
    end
  end

  defp metadata_key(record), do: record |> Payments.parent_key() |> to_string()
end
