defmodule Edenflowers.Orders.Changes.CancelOpenPaymentIntent do
  @moduledoc """
  Cancels the PaymentIntent waiting on the order's payment link, when the
  order is cancelled or paid in person, so the link can't charge a stale
  amount. Opening the link again starts a fresh PaymentIntent for whatever
  the balance is then.

  If the customer has already paid, Stripe refuses the cancel and the
  succeeded webhook records the payment anyway; the balance then shows the
  difference to refund.
  """
  use Ash.Resource.Change

  require Logger

  @impl true
  def change(%{data: %{payment_intent_id: nil}} = changeset, _opts, _context), do: changeset

  def change(%{data: %{payment_intent_id: payment_intent_id}} = changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.force_change_attribute(:payment_intent_id, nil)
    |> Ash.Changeset.after_transaction(fn
      _changeset, {:ok, order} ->
        case stripe_api().cancel_payment_intent(%{id: payment_intent_id}) do
          {:ok, _payment_intent} ->
            :ok

          {:error, reason} ->
            Logger.warning(
              "Could not cancel PaymentIntent #{payment_intent_id} for order #{order.id}: #{inspect(reason)}"
            )
        end

        {:ok, order}

      _changeset, error ->
        error
    end)
  end

  defp stripe_api, do: Application.get_env(:edenflowers, :stripe_api, Edenflowers.External.StripeAPI)
end
