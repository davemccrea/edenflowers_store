defmodule Edenflowers.Store.CartLineItem.Changes.PopulateFromVariant do
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Store.ProductVariant

  @impl true
  def change(changeset, _opts, _context) do
    variant_id = Ash.Changeset.get_attribute(changeset, :product_variant_id)

    with id when not is_nil(id) <- variant_id,
         {:ok, variant} <-
           Ash.get(ProductVariant, id, load: [product: [:tax_rate]], authorize?: false) do
      attrs = %{
        product_id: variant.product.id,
        product_name: variant.product.name,
        product_image_slug: variant.image_slug,
        unit_price: variant.price,
        tax_rate: variant.product.tax_rate.percentage
      }

      attrs =
        if Ash.Changeset.get_attribute(changeset, :is_card) do
          Map.put(attrs, :card_size, variant.size)
        else
          attrs
        end

      Ash.Changeset.force_change_attributes(changeset, attrs)
    else
      _ ->
        Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
          field: :product_variant_id,
          message: ~t"is invalid"
        })
    end
  end
end
