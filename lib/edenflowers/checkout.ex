defmodule Edenflowers.Checkout do
  @moduledoc """
  Orchestrates the checkout payment lifecycle.

  This module sits between the web layer (LiveViews, controllers) and the
  Stripe API port. It owns creating, retrieving, updating and persisting
  payment intents so that callers only need one function per step.
  """

  require Logger

  alias Edenflowers.Store.Order

  defp stripe_api, do: Application.get_env(:edenflowers, :stripe_api, Edenflowers.StripeAPI)

  @doc """
  Sets up the payment for an order that has reached the payment step.

  * If the order has no `payment_intent_id`, a new PaymentIntent is created
    on Stripe and the id is persisted on the order.
  * If the order already has a `payment_intent_id`, the existing intent is
    retrieved from Stripe.

  Returns `{:ok, updated_order, client_secret}` or `{:error, reason}`.
  """
  def setup_payment(%{payment_intent_id: nil} = order, actor) do
    case stripe_api().create_payment_intent(order) do
      {:ok, payment_intent} ->
        persist_payment_intent(order, payment_intent, actor)

      {:error, reason} ->
        Logger.error("Failed to create payment intent for order #{order.id}: #{inspect(reason)}")
        {:error, :payment_intent_create_failed}
    end
  end

  def setup_payment(order, _actor) do
    case stripe_api().retrieve_payment_intent(order) do
      {:ok, payment_intent} ->
        {:ok, order, payment_intent.client_secret}

      {:error, reason} ->
        Logger.error("Failed to retrieve payment intent for order #{order.id}: #{inspect(reason)}")
        {:error, :payment_intent_retrieve_failed}
    end
  end

  @doc """
  Updates the PaymentIntent amount to match the order's current total.

  Returns `{:ok, payment_intent}` or `{:error, reason}`.
  """
  def update_payment(order) do
    stripe_api().update_payment_intent(order)
  end

  # =======
  # Private
  # =======

  defp persist_payment_intent(order, payment_intent, actor) do
    case Order.add_payment_intent_id(order, payment_intent.id, actor: actor) do
      {:ok, order} ->
        {:ok, order, payment_intent.client_secret}

      {:error, reason} ->
        # Persisting the id failed — cancel the orphan intent on Stripe so it
        # doesn't linger in the dashboard. Best-effort.
        stripe_api().cancel_payment_intent(payment_intent)

        Logger.error("Failed to persist payment_intent_id for order #{order.id}: #{inspect(reason)}")

        {:error, :payment_intent_persist_failed}
    end
  end
end
