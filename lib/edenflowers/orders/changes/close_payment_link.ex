defmodule Edenflowers.Orders.Changes.ClosePaymentLink do
  @moduledoc """
  Cancels the order's PaymentIntent once the order is paid in person or
  cancelled, so the payment link can't take a second payment. If the customer
  has already paid online, Stripe refuses the cancel and the succeeded webhook
  reports the double payment.
  """
  use Ash.Resource.Change

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn
      _changeset, {:ok, %{payment_intent_id: payment_intent_id} = order} when is_binary(payment_intent_id) ->
        case stripe_api().cancel_payment_intent(%{id: payment_intent_id}) do
          {:ok, _payment_intent} ->
            :ok

          {:error, reason} ->
            Logger.warning(
              "Could not cancel PaymentIntent #{payment_intent_id} for order #{order.id}: #{inspect(reason)}"
            )
        end

        {:ok, order}

      _changeset, result ->
        result
    end)
  end

  defp stripe_api, do: Application.get_env(:edenflowers, :stripe_api, Edenflowers.External.StripeAPI)
end
