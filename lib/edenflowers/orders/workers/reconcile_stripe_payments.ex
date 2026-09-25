defmodule Edenflowers.Orders.Workers.ReconcileStripePayments do
  @moduledoc """
  Safety net for the Stripe webhook. Places orders and confirms course bookings
  whose PaymentIntent succeeded but which were never updated, e.g. because the
  webhook endpoint is misconfigured or was unreachable. Anything completed here
  is logged as an error, since it means the webhook is not working.
  """

  use Oban.Worker, max_attempts: 1

  require Ash.Query
  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Courses
  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Orders
  alias Edenflowers.Orders.{Order, Payment}

  # Give the webhook time to arrive before stepping in.
  @grace_period_minutes 5
  # Older checkouts are abandoned; don't keep asking Stripe about them.
  @lookback_days 7
  # Long enough for a slow 3DS challenge to finish before the lock is dropped.
  @abandoned_lock_minutes 60
  @unconfirmed_statuses ["requires_payment_method", "requires_confirmation", "requires_action"]

  @impl true
  def perform(_job) do
    Enum.each(stale_payment_orders(), &reconcile/1)
    Enum.each(stale_course_registrations(), &reconcile_registration/1)
  end

  defp stale_payment_orders do
    now = DateTime.utc_now()
    settled_before = DateTime.add(now, -@grace_period_minutes, :minute)

    Order
    |> Ash.Query.filter(
      state == :confirming_payment and not is_nil(payment_intent_id) and
        updated_at < ^settled_before
    )
    |> Ash.read!(actor: system_actor())
  end

  defp stale_course_registrations do
    now = DateTime.utc_now()
    settled_before = DateTime.add(now, -@grace_period_minutes, :minute)
    abandoned_before = DateTime.add(now, -@lookback_days, :day)

    CourseRegistration
    |> Ash.Query.filter(
      status == :pending and not is_nil(payment_intent_id) and
        updated_at < ^settled_before and updated_at > ^abandoned_before
    )
    |> Ash.read!(actor: system_actor())
  end

  defp reconcile_registration(registration) do
    with {:ok, %{status: "succeeded"} = payment_intent} <- stripe_api().retrieve_payment_intent(registration),
         {:ok, %CourseRegistration{}} <- Courses.Payment.complete_payment(registration.id, payment_intent) do
      Logger.error(
        "Reconciliation confirmed course registration #{registration.id} for succeeded PaymentIntent " <>
          "#{payment_intent.id}. The Stripe payment_intent.succeeded webhook did not arrive; check the webhook endpoint."
      )
    else
      {:ok, _not_succeeded_or_already_confirmed} ->
        :ok

      {:error, reason} ->
        Logger.error("Reconciliation failed for course registration #{registration.id}: #{inspect(reason)}")
    end
  end

  defp reconcile(order) do
    case stripe_api().retrieve_payment_intent(order) do
      {:ok, %{status: "succeeded"} = payment_intent} ->
        complete_payment(order, payment_intent)

      {:ok, %{status: "canceled", id: payment_intent_id}}
      when payment_intent_id == order.payment_intent_id ->
        Orders.cancel_payment_confirmation(order, actor: system_actor())

      {:ok, %{status: status} = payment_intent} when status in @unconfirmed_statuses ->
        maybe_release_abandoned_lock(order, payment_intent)

      {:ok, _not_succeeded} ->
        :ok

      {:error, reason} ->
        Logger.error("Reconciliation: failed to retrieve PaymentIntent for order #{order.id}: #{inspect(reason)}")
    end
  end

  # Canceling rather than releasing, so a customer who returns to a 3DS tab
  # cannot complete a payment for an order they may have since edited.
  defp maybe_release_abandoned_lock(order, payment_intent) do
    abandoned_before = DateTime.add(DateTime.utc_now(), -@abandoned_lock_minutes, :minute)

    if DateTime.before?(order.updated_at, abandoned_before) do
      with {:ok, _canceled} <- stripe_api().cancel_payment_intent(payment_intent),
           {:ok, _order} <- Orders.cancel_payment_confirmation(order, actor: system_actor()) do
        :ok
      else
        {:error, reason} ->
          Logger.error("Reconciliation failed to release abandoned order #{order.id}: #{inspect(reason)}")
      end
    else
      :ok
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
