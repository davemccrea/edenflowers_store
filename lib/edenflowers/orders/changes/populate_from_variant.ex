defmodule Edenflowers.Orders.Changes.PopulateFromVariant do
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Catalog

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &populate/1)
  end

  defp populate(changeset) do
    variant_id = Ash.Changeset.get_attribute(changeset, :product_variant_id)

    with id when not is_nil(id) <- variant_id,
         {:ok, variant} <-
           Catalog.get_variant_by_id(id, load: [product: [:tax_rate]], authorize?: false) do
      attrs = %{
        product_id: variant.product.id,
        product_name: variant.product.name,
        product_image_slug: variant.image_slug,
        unit_price: variant.price,
        tax_rate: variant.product.tax_rate.percentage,
        variant_size: variant.size,
        free_delivery: variant.product.free_delivery
      }

      if Ash.Changeset.get_attribute(changeset, :interval_weeks) && not variant.product.subscribable do
        Ash.Changeset.add_error(changeset, field: :interval_weeks, message: ~t"This product can't be subscribed to")
      else
        Ash.Changeset.force_change_attributes(changeset, attrs)
      end
    else
      _ ->
        Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
          field: :product_variant_id,
          message: ~t"is invalid"
        })
    end
  end
end
