defmodule Edenflowers.Orders.Workers.ReconcileStripePayments do
  @moduledoc """
  Safety net for the Stripe webhook. Places orders and confirms course bookings
  whose PaymentIntent succeeded but which were never updated, e.g. because the
  webhook endpoint is misconfigured or was unreachable. Anything completed here
  is logged as an error, since it means the webhook is not working.
  """

  use Oban.Worker, max_attempts: 1

  require Logger

  alias Edenflowers.Payments

  # Give the webhook time to arrive before stepping in.
  @grace_period_minutes 5
  # Older checkouts are abandoned; don't keep asking Stripe about them.
  @lookback_days 7

  @impl true
  def perform(_job) do
    now = DateTime.utc_now()
    settled_before = DateTime.add(now, -@grace_period_minutes, :minute)
    abandoned_before = DateTime.add(now, -@lookback_days, :day)

    for adapter <- Payments.adapters(),
        payable <- adapter.awaiting_payment(settled_before, abandoned_before) do
      reconcile(adapter, payable)
    end

    :ok
  end

  defp reconcile(adapter, payable) do
    case Payments.reconcile(payable) do
      {:ok, :completed} ->
        Logger.error(
          "Reconciliation completed #{adapter.metadata_key()} #{payable.id} for its succeeded PaymentIntent " <>
            "#{payable.payment_intent_id}. The Stripe payment_intent.succeeded webhook did not arrive; " <>
            "check the webhook endpoint."
        )

      {:ok, _already_completed_or_not_succeeded} ->
        :ok

      {:error, reason} ->
        Logger.error("Reconciliation failed for #{adapter.metadata_key()} #{payable.id}: #{inspect(reason)}")
    end
  end
end
