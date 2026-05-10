defmodule EdenflowersWeb.StripeHandler do
  @behaviour Stripe.WebhookHandler

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Store.Cart
  alias Edenflowers.Workers.SendOrderConfirmationEmail

  @impl true
  def handle_event(%Stripe.Event{type: "charge.succeeded"} = _event) do
    # Charge events are handled via payment_intent.succeeded
    :ok
  end

  @impl true
  def handle_event(%Stripe.Event{type: "payment_intent.succeeded"} = event) do
    # Always re-enqueue on success: the worker has a unique constraint on
    # `order_id`, so a redelivered webhook collapses to the existing job, and a
    # prior delivery that converted but failed to enqueue gets a second chance.
    with {:ok, cart_id} <- fetch_cart_id(event),
         {:ok, order_id} <- convert(cart_id),
         {:ok, _job} <- SendOrderConfirmationEmail.enqueue(%{"order_id" => order_id}) do
      :ok
    else
      {:error, :missing_cart_id} ->
        Logger.warning("Stripe payment_intent.succeeded event #{event.id} is missing cart_id metadata")

        :error

      {:error, {:conversion_failed, cart_id, reason}} ->
        Logger.error(
          "Failed to convert cart #{cart_id} for Stripe payment_intent.succeeded event #{event.id}: #{inspect(reason)}"
        )

        :error

      {:error, {:enqueue_failed, order_id, changeset}} ->
        Logger.error(
          "Failed to enqueue Oban job for order #{order_id} with Stripe payment_intent.succeeded event #{event.id}): #{inspect(changeset)}"
        )

        :error
    end
  end

  @impl true
  def handle_event(%Stripe.Event{type: type} = event)
      when type in ["payment_intent.payment_failed", "payment_intent.canceled"] do
    with {:ok, cart_id} <- fetch_cart_id(event),
         {:ok, outcome} <- mark_payment_failed(cart_id) do
      case outcome do
        :already_converted ->
          # A succeeded event arrived first (or was reprocessed). Don't downgrade.
          :ok

        _cart ->
          Logger.info("Marked cart #{cart_id} payment as failed for Stripe #{type} event #{event.id}")

          :ok
      end
    else
      {:error, :missing_cart_id} ->
        Logger.warning("Stripe #{type} event #{event.id} is missing cart_id metadata")
        :error

      {:error, {:payment_update_failed, cart_id, reason}} ->
        Logger.error(
          "Failed to mark cart #{cart_id} as failed for Stripe #{type} event #{event.id}: #{inspect(reason)}"
        )

        :error
    end
  end

  @impl true
  def handle_event(%Stripe.Event{type: type} = _event) do
    Logger.warning("Unhandled Stripe event: #{type}")
    :ok
  end

  defp fetch_cart_id(%Stripe.Event{data: %{object: %{metadata: %{"cart_id" => cart_id}}}})
       when is_binary(cart_id) and cart_id != "" do
    {:ok, cart_id}
  end

  defp fetch_cart_id(_event), do: {:error, :missing_cart_id}

  # Idempotent: if the cart has already been converted (state == :converted),
  # we surface its existing order_id so the email enqueue still happens.
  defp convert(cart_id) do
    with {:ok, cart} <- Cart.get_by_id(cart_id, actor: system_actor()) do
      case cart.state do
        :converted ->
          {:ok, cart.order_id}

        _ ->
          case Cart.convert(cart, actor: system_actor()) do
            {:ok, converted} -> {:ok, converted.order_id}
            {:error, reason} -> {:error, {:conversion_failed, cart_id, reason}}
          end
      end
    else
      {:error, reason} -> {:error, {:conversion_failed, cart_id, reason}}
    end
  end

  defp mark_payment_failed(cart_id) do
    with {:ok, cart} <- Cart.get_by_id(cart_id, actor: system_actor()) do
      case cart.state do
        :converted ->
          {:ok, :already_converted}

        _ ->
          case Cart.mark_payment_failed(cart, actor: system_actor()) do
            {:ok, cart} -> {:ok, cart}
            {:error, reason} -> {:error, {:payment_update_failed, cart_id, reason}}
          end
      end
    else
      {:error, reason} -> {:error, {:payment_update_failed, cart_id, reason}}
    end
  end
end
