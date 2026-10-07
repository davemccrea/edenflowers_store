defmodule Edenflowers.Payments.Changes.CancelOpenPaymentIntent do
  @moduledoc "Clears a resource's attached PaymentIntent and cancels it in Stripe once committed."

  use Ash.Resource.Change

  require Logger

  @impl true
  def change(%{data: %{payment_intent_id: nil}} = changeset, _opts, _context), do: changeset

  def change(%{data: %{payment_intent_id: payment_intent_id}} = changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.force_change_attribute(:payment_intent_id, nil)
    |> Ash.Changeset.after_transaction(fn
      _changeset, {:ok, record} ->
        case stripe_api().cancel_payment_intent(%{id: payment_intent_id}) do
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

  defp stripe_api, do: Application.get_env(:edenflowers, :stripe_api, Edenflowers.External.StripeAPI)
end
