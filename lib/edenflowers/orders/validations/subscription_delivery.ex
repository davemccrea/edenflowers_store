defmodule Edenflowers.Orders.Validations.SubscriptionDelivery do
  @moduledoc "A subscription cart is delivered, never picked up."
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @impl true
  def validate(changeset, _opts, context) do
    if subscription?(changeset.data, context) and
         Ash.Changeset.get_attribute(changeset, :fulfillment_method) != :delivery do
      {:error, field: :fulfillment_option_id, message: ~t"A subscription can only be delivered"}
    else
      :ok
    end
  end

  defp subscription?(order, context) do
    Ash.load!(order, :subscription?, Ash.Context.to_opts(context, lazy?: true)).subscription?
  end
end
