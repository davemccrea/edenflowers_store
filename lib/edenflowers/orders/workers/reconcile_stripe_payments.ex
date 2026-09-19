defmodule Edenflowers.Orders.Workers.ReconcileStripePayments do
  @moduledoc """
  Safety net for the Stripe webhook. Places orders whose PaymentIntent succeeded
  but which are still in checkout, e.g. because the webhook endpoint is
  misconfigured or was unreachable. Any order placed here is logged as an error,
  since it means the webhook is not working.
  """

  use Oban.Worker, max_attempts: 1

  require Ash.Query
  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Orders.{Order, Payment}

  # Give the webhook time to arrive before stepping in.
  @grace_period_minutes 5
  # Older checkouts are abandoned; don't keep asking Stripe about them.
  @lookback_days 7

  @impl true
  def perform(_job) do
    Enum.each(stale_payment_orders(), &reconcile/1)
  end

  defp stale_payment_orders do
    now = DateTime.utc_now()
    settled_before = DateTime.add(now, -@grace_period_minutes, :minute)
    abandoned_before = DateTime.add(now, -@lookback_days, :day)

    Order
    |> Ash.Query.filter(
      state == :payment and not is_nil(payment_intent_id) and
        updated_at < ^settled_before and updated_at > ^abandoned_before
    )
    |> Ash.read!(actor: system_actor())
  end

  defp reconcile(order) do
    case stripe_api().retrieve_payment_intent(order) do
      {:ok, %{status: "succeeded"} = payment_intent} ->
        complete_payment(order, payment_intent)

      {:ok, _not_succeeded} ->
        :ok

      {:error, reason} ->
        Logger.error("Reconciliation: failed to retrieve PaymentIntent for order #{order.id}: #{inspect(reason)}")
    end
  end

  defp complete_payment(order, payment_intent) do
    case Payment.complete_payment(order.id, payment_intent) do
      {:ok, :already_placed} ->
        :ok

      {:ok, _placed} ->
        Logger.error(
          "Reconciliation placed order #{order.id} for succeeded PaymentIntent #{payment_intent.id}. " <>
            "The Stripe payment_intent.succeeded webhook did not arrive; check the webhook endpoint."
        )

      {:error, reason} ->
        Logger.error("Reconciliation failed to place order #{order.id}: #{inspect(reason)}")
    end
  end

  defp stripe_api, do: Application.get_env(:edenflowers, :stripe_api, Edenflowers.External.StripeAPI)
end
