defmodule Edenflowers.Payments.Changes.CancelOpenPaymentIntent do
  @moduledoc """
  Clears a resource's attached PaymentIntent and cancels it in Stripe once committed.

  With `before_commit?: true` it cancels first and stops the change when Stripe
  refuses, as it does for a payment already under way. For a delete, which would
  otherwise leave that payment no record to land on.
  """

  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  require Logger

  alias Edenflowers.External.StripeAPI

  @impl true
  def change(%{data: %{payment_intent_id: nil}} = changeset, _opts, _context), do: changeset

  def change(%{data: %{payment_intent_id: payment_intent_id}} = changeset, opts, _context) do
    changeset = Ash.Changeset.force_change_attribute(changeset, :payment_intent_id, nil)

    if opts[:before_commit?],
      do: cancel_before_commit(changeset, payment_intent_id),
      else: cancel_after_commit(changeset, payment_intent_id)
  end

  defp cancel_before_commit(changeset, payment_intent_id) do
    Ash.Changeset.before_transaction(changeset, fn changeset ->
      if cancelled?(payment_intent_id) do
        changeset
      else
        Ash.Changeset.add_error(
          changeset,
          ~t"A payment for this order is under way. Wait for it to arrive, then cancel the order instead."
        )
      end
    end)
  end

  # Stripe refuses to cancel twice, so an earlier cancel is checked for.
  defp cancelled?(payment_intent_id) do
    case StripeAPI.impl().cancel_payment_intent(%{id: payment_intent_id}) do
      {:ok, _payment_intent} ->
        true

      {:error, reason} ->
        Logger.warning("Could not cancel PaymentIntent #{payment_intent_id}: #{inspect(reason)}")

        match?(
          {:ok, %{status: "canceled"}},
          StripeAPI.impl().retrieve_payment_intent(%{payment_intent_id: payment_intent_id})
        )
    end
  end

  defp cancel_after_commit(changeset, payment_intent_id) do
    Ash.Changeset.after_transaction(changeset, fn
      _changeset, {:ok, record} ->
        case StripeAPI.impl().cancel_payment_intent(%{id: payment_intent_id}) do
          {:ok, _payment_intent} ->
            :ok

          {:error, reason} ->
            Logger.warning(
              "Could not cancel PaymentIntent #{payment_intent_id} for #{inspect(record.__struct__)} #{record.id}: #{inspect(reason)}"
            )
        end

        {:ok, record}

      _changeset, error ->
        error
    end)
  end
end
