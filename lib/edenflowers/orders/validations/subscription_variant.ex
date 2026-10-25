defmodule Edenflowers.Orders.Validations.SubscriptionVariant do
  @moduledoc """
  A subscription changes size only to another size of the same subscription
  product, so it can't be switched to an ordinary bouquet.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Catalog

  @impl true
  def validate(changeset, _opts, context) do
    new_id = Ash.Changeset.get_attribute(changeset, :product_variant_id)

    if new_id == changeset.data.product_variant_id do
      :ok
    else
      sizes = Catalog.list_subscription_sizes!(changeset.data.product_variant_id, Ash.Context.to_opts(context))

      if Enum.any?(sizes, &(&1.id == new_id)) do
        :ok
      else
        {:error, field: :product_variant_id, message: ~t"Choose one of the sizes on offer."}
      end
    end
  end
end
