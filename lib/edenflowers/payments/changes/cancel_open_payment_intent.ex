defmodule Edenflowers.Payments.Changes.CancelOpenPaymentIntent do
  @moduledoc """
  Clears a resource's attached PaymentIntent and cancels it in Stripe once committed.

  With `before_commit?: true` it cancels first and stops the change when Stripe
  refuses, as it does for a payment already under way. For a delete, which would
  otherwise leave that payment no record to land on.
  """

  use Ash.Resource.Change

  require Logger

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Payments.Errors.PaymentInProgress

  @impl true
  def change(changeset, opts, _context) do
    if opts[:before_commit?],
      do: Ash.Changeset.before_transaction(changeset, &cancel_before_commit/1),
      else: cancel_after_commit(changeset, changeset.data.payment_intent_id)
  end

  defp cancel_before_commit(changeset) do
    case Ash.reload(changeset.data, authorize?: false) do
      {:ok, %{payment_intent_id: checked_id}} ->
        # Its cancellation webhook may clear this intent; a different one must stop deletion.
        filter =
          if is_nil(checked_id),
            do: expr(is_nil(payment_intent_id)),
            else: expr(is_nil(payment_intent_id) or payment_intent_id == ^checked_id)

        changeset =
          changeset
          |> Ash.Changeset.filter(filter)
          |> Ash.Changeset.force_change_attribute(:payment_intent_id, nil)

        case cancel(checked_id) do
          :ok -> changeset
          {:error, error} -> Ash.Changeset.add_error(changeset, error)
        end

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end

  defp cancel(nil), do: :ok

  # Stripe refuses to cancel twice, so an earlier cancel is checked for.
  defp cancel(payment_intent_id) do
    case StripeAPI.impl().cancel_payment_intent(%{id: payment_intent_id}) do
      {:ok, _payment_intent} ->
        :ok

      {:error, reason} ->
        Logger.warning("Could not cancel PaymentIntent #{payment_intent_id}: #{inspect(reason)}")

        case StripeAPI.impl().retrieve_payment_intent(%{payment_intent_id: payment_intent_id}) do
          {:ok, %{status: "canceled"}} ->
            :ok

          {:ok, %{status: status}} when status in ["processing", "succeeded"] ->
            {:error, PaymentInProgress.exception(field: :payment_intent_id)}

          {:ok, _payment_intent} ->
            {:error, "Could not cancel PaymentIntent: #{inspect(reason)}"}

          {:error, error} ->
            {:error, "Could not verify PaymentIntent cancellation: #{inspect(error)}"}
        end
    end
  end

  defp cancel_after_commit(changeset, nil), do: changeset

  defp cancel_after_commit(changeset, payment_intent_id) do
    changeset
    |> Ash.Changeset.force_change_attribute(:payment_intent_id, nil)
    |> Ash.Changeset.after_transaction(fn
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
