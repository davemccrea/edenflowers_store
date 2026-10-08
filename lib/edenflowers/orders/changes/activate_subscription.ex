defmodule Edenflowers.Orders.Changes.ActivateSubscription do
  @moduledoc """
  Starts the Subscription a paid subscription cart asked for, from the order's
  delivery details and the card Stripe saved, and links the order to it as its
  first delivery.

  Run by the `:start_subscription` trigger once the order is placed, so a
  failure fails the job, which retries, and the order stays placed.
  """
  use Ash.Resource.Change

  alias Edenflowers.Orders

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      with {:ok, order} <- Ash.load(changeset.data, :line_items, Ash.Context.to_opts(context)),
           {:ok, subscription} <- Orders.activate_subscription(attributes(order), Ash.Context.to_opts(context)) do
        Ash.Changeset.force_change_attribute(changeset, :subscription_id, subscription.id)
      else
        {:error, error} -> Ash.Changeset.add_error(changeset, error)
      end
    end)
  end

  defp attributes(order) do
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
      stripe_customer_id: order.stripe_customer_id,
      stripe_payment_method_id: order.stripe_payment_method_id
    }
  end
end
