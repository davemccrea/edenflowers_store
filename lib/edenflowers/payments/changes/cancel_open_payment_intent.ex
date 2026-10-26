defmodule Edenflowers.Payments.Changes.CancelOpenPaymentIntent do
  @moduledoc """
  Cancels an attached PaymentIntent once committed, clearing it only after Stripe agrees.

  With `before_commit?: true` it cancels first and stops the change when Stripe
  refuses, as it does for a payment already under way. For a delete, which would
  otherwise leave that payment no record to land on.
  """

  use Ash.Resource.Change

  require Logger

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Payments.Errors.PaymentInProgress
  import Edenflowers.Actors

  @impl true
  def change(%{data: %{payment_intent_id: nil}} = changeset, _opts, _context), do: changeset

  def change(%{data: %{payment_intent_id: payment_intent_id}} = changeset, opts, _context) do
    if opts[:before_commit?],
      do:
        cancel_before_commit(
          Ash.Changeset.force_change_attribute(changeset, :payment_intent_id, nil),
          payment_intent_id
        ),
      else: cancel_after_commit(changeset, payment_intent_id)
  end

  defp cancel_before_commit(changeset, payment_intent_id) do
    Ash.Changeset.before_transaction(changeset, fn changeset ->
      if cancelled?(payment_intent_id) do
        changeset
      else
        Ash.Changeset.add_error(changeset, PaymentInProgress.exception(field: :payment_intent_id))
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
          {:ok, _cancelled} ->
            case Ash.update(record, %{payment_intent_id: payment_intent_id},
                   action: :mark_payment_cancelled,
                   actor: system_actor()
                 ) do
              {:ok, cleared} -> {:ok, cleared}
              {:error, _changed_meanwhile} -> {:ok, record}
            end

          {:error, reason} ->
            Logger.warning("Could not cancel PaymentIntent #{payment_intent_id}: #{inspect(reason)}")
            {:ok, record}
        end

      _changeset, error ->
        error
    end)
  end
end
