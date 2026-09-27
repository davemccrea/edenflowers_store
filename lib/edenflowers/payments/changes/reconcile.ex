defmodule Edenflowers.Payments.Changes.Reconcile do
  use Ash.Resource.Change

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case Edenflowers.Payments.reconcile(changeset.data) do
        {:ok, :completed} ->
          Logger.error(
            "Reconciliation completed #{inspect(changeset.resource)} #{changeset.data.id} for its succeeded PaymentIntent " <>
              "#{changeset.data.payment_intent_id}. The Stripe payment_intent.succeeded webhook did not arrive; " <>
              "check the webhook endpoint."
          )

          changeset

        {:ok, _already_completed_or_not_succeeded} ->
          changeset

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    end)
  end
end
