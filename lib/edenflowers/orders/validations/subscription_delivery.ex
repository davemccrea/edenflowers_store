defmodule Edenflowers.Orders.Validations.SubscriptionDelivery do
  @moduledoc "A subscription cart is delivered, never picked up, and says how often."
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Orders.Subscription

  @impl true
  def validate(changeset, _opts, _context) do
    if subscription?(changeset.data) do
      cond do
        Ash.Changeset.get_attribute(changeset, :fulfillment_method) != :delivery ->
          {:error, field: :fulfillment_option_id, message: ~t"A subscription can only be delivered"}

        Ash.Changeset.get_attribute(changeset, :subscription_interval_weeks) not in Subscription.intervals() ->
          {:error, field: :subscription_interval_weeks, message: ~t"Choose how often"}

        true ->
          :ok
      end
    else
      :ok
    end
  end

  defp subscription?(%{subscription?: subscription?}) when is_boolean(subscription?), do: subscription?
  defp subscription?(order), do: Ash.load!(order, :subscription?, authorize?: false).subscription?
end
