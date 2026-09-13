defmodule Edenflowers.Orders.Payment do
  @moduledoc """
  Orchestrates Stripe payments for orders during checkout.
  """

  require Logger

  alias Edenflowers.Orders

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

  def update_payment(order), do: stripe_api().update_payment_intent(order)

  defp persist_payment_intent(order, payment_intent, actor) do
    case Orders.add_payment_intent_id(order, payment_intent.id, actor: actor) do
      {:ok, order} ->
        {:ok, order, payment_intent.client_secret}

      {:error, reason} ->
        stripe_api().cancel_payment_intent(payment_intent)

        Logger.error("Failed to persist payment_intent_id for order #{order.id}: #{inspect(reason)}")

        {:error, :payment_intent_persist_failed}
    end
  end

  defp stripe_api, do: Application.get_env(:edenflowers, :stripe_api, Edenflowers.External.StripeAPI)
end
