defmodule Edenflowers.Payments.Changes.CancelOpenPaymentIntent do
  @moduledoc """
  Cancels an attached PaymentIntent once committed, clearing it only after Stripe agrees.

  A processing or failed cancellation leaves the reference recoverable. Purchases
  are retained, so a delayed success can still record its actual money.
  """

  use Ash.Resource.Change

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.External.StripeAPI

  @impl true
  def change(%{data: %{payment_intent_id: nil}} = changeset, _opts, _context), do: changeset

  def change(%{data: %{payment_intent_id: payment_intent_id}} = changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn
      _changeset, {:ok, record} ->
        case StripeAPI.impl().cancel_payment_intent(%{id: payment_intent_id}) do
          {:ok, %{status: "canceled"}} ->
            clear_cancelled(record, payment_intent_id)

          {:ok, _nonterminal} ->
            Logger.warning("PaymentIntent #{payment_intent_id} is not cancelled; retaining its reference")
            {:ok, record}

          {:error, reason} ->
            Logger.warning("Could not cancel PaymentIntent #{payment_intent_id}: #{inspect(reason)}")
            {:ok, record}
        end

      _changeset, error ->
        error
    end)
  end

  defp clear_cancelled(record, payment_intent_id) do
    case Ash.update(record, %{payment_intent_id: payment_intent_id},
           action: :mark_payment_cancelled,
           actor: system_actor()
         ) do
      {:ok, cleared} -> {:ok, cleared}
      {:error, _changed_meanwhile} -> {:ok, record}
    end
  end
end
