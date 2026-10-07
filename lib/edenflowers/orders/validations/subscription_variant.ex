defmodule Edenflowers.Orders.Validations.SubscriptionVariant do
  @moduledoc """
  A subscription changes size only to another size of the same subscription
  product, so it can't be switched to an ordinary bouquet.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Catalog.ProductVariant

  @impl true
  def validate(changeset, _opts, _context) do
    new_id = Ash.Changeset.get_attribute(changeset, :product_variant_id)

    if new_id == changeset.data.product_variant_id do
      :ok
    else
      %{product_id: product_id} = Ash.get!(ProductVariant, changeset.data.product_variant_id, authorize?: false)

      case Ash.get(ProductVariant, new_id, authorize?: false) do
        {:ok, %{product_id: ^product_id, draft: false}} -> :ok
        _other -> {:error, field: :product_variant_id, message: ~t"Choose one of the sizes on offer."}
      end
    end
  end
end
