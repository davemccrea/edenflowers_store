defmodule Edenflowers.Payments.Changes.CancelOpenPaymentIntent do
  @moduledoc "Cancels a resource's attached PaymentIntent after clearing it transactionally."

  use Ash.Resource.Change

  require Ash.Query
  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      id = changeset.data.id

      record =
        changeset.resource
        |> Ash.Query.filter(id == ^id)
        |> Ash.Query.lock(:for_update)
        |> Ash.read_one!(authorize?: false)

      changeset
      |> Ash.Changeset.force_change_attribute(:payment_intent_id, nil)
      |> Ash.Changeset.after_transaction(&cancel_payment_intent(&1, &2, record.payment_intent_id))
    end)
  end

  defp cancel_payment_intent(_changeset, result, nil), do: result

  defp cancel_payment_intent(_changeset, {:ok, record}, payment_intent_id) do
    case stripe_api().cancel_payment_intent(%{id: payment_intent_id}) do
      {:ok, _payment_intent} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Could not cancel PaymentIntent #{payment_intent_id} for #{inspect(record.__struct__)} #{record.id}: #{inspect(reason)}"
        )
    end

    {:ok, record}
  end

  defp cancel_payment_intent(_changeset, error, _payment_intent_id), do: error

  defp stripe_api, do: Application.get_env(:edenflowers, :stripe_api, Edenflowers.External.StripeAPI)
end
