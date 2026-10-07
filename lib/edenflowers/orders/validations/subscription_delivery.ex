defmodule Edenflowers.Orders.Validations.SubscriptionDelivery do
  @moduledoc "A subscription cart is delivered, never picked up."
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @impl true
  def validate(changeset, _opts, _context) do
    if subscription?(changeset.data) and Ash.Changeset.get_attribute(changeset, :fulfillment_method) != :delivery do
      {:error, field: :fulfillment_option_id, message: ~t"A subscription can only be delivered"}
    else
      :ok
    end
  end

  defp subscription?(%{subscription?: subscription?}) when is_boolean(subscription?), do: subscription?
  defp subscription?(order), do: Ash.load!(order, :subscription?, authorize?: false).subscription?
end
