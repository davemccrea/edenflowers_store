defmodule Edenflowers.Orders.Changes.ActivateSubscription do
  @moduledoc """
  When a subscription cart is paid, starts the Subscription from the order's
  delivery details and the card Stripe saved, and links the order to it as
  its first delivery.

  Runs in finalize_checkout's transaction, which only ever places an order
  once, so a redelivered webhook can't start a second subscription.

  The money has already moved, so a subscription that can't be started never
  stops the order being placed (ADR 0002). It is logged as an error so it
  reaches ErrorTracker and Jennie can contact the customer.
  """
  use Ash.Resource.Change

  require Logger

  alias Edenflowers.Orders.Subscription

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &activate/1)
  end

  defp activate(changeset) do
    order = Ash.load!(changeset.data, [:subscription?, :line_items], authorize?: false)

    if order.subscription? do
      Subscription
      |> Ash.Changeset.for_create(:activate, attributes(order, changeset), authorize?: false)
      |> Ash.create()
      |> case do
        {:ok, subscription} ->
          Ash.Changeset.force_change_attribute(changeset, :subscription_id, subscription.id)

        {:error, error} ->
          Logger.error(
            "Order #{order.id} was paid but its subscription could not be started: #{Exception.message(error)}"
          )

          changeset
      end
    else
      changeset
    end
  end

  defp attributes(order, changeset) do
    line_item = Enum.find(order.line_items, & &1.interval_weeks)

    %{
      user_id: order.user_id,
      product_variant_id: line_item.product_variant_id,
      interval_weeks: line_item.interval_weeks,
      next_fulfillment_date: Date.add(order.fulfillment_date, line_item.interval_weeks * 7),
      recipient_name: order.recipient_name,
      recipient_phone_number: order.recipient_phone_number,
      delivery_address: order.delivery_address,
      delivery_instructions: order.delivery_instructions,
      fulfillment_option_id: order.fulfillment_option_id,
      card_message: order.card_message,
      locale: order.locale,
      stripe_customer_id: Ash.Changeset.get_argument(changeset, :stripe_customer_id),
      stripe_payment_method_id: Ash.Changeset.get_argument(changeset, :stripe_payment_method_id)
    }
  end
end
