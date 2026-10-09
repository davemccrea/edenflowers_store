defmodule Edenflowers.Orders.Changes.SnapshotCard do
  @moduledoc """
  Copies the brand, last four digits and expiry of the subscription's saved
  card from Stripe, so the account page can say which card is charged. The
  card is only shown, so a failed lookup leaves the details blank rather than
  failing the change.
  """
  use Ash.Resource.Change

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      payment_method_id = Ash.Changeset.get_attribute(changeset, :stripe_payment_method_id)

      case Edenflowers.External.StripeAPI.impl().retrieve_payment_method(payment_method_id) do
        {:ok, %{card: %{brand: brand, last4: last4, exp_month: exp_month, exp_year: exp_year}}} ->
          Ash.Changeset.force_change_attributes(changeset, %{
            card_brand: brand,
            card_last4: last4,
            card_exp_month: exp_month,
            card_exp_year: exp_year
          })

        {:ok, _not_a_card} ->
          clear(changeset)

        {:error, reason} ->
          Logger.warning("Couldn't look up payment method #{payment_method_id}: #{inspect(reason)}")
          clear(changeset)
      end
    end)
  end

  defp clear(changeset) do
    Ash.Changeset.force_change_attributes(changeset, %{
      card_brand: nil,
      card_last4: nil,
      card_exp_month: nil,
      card_exp_year: nil
    })
  end
end
