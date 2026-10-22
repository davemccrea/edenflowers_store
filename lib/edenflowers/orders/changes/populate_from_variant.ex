defmodule Edenflowers.Orders.Changes.PopulateFromVariant do
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Catalog
  alias Edenflowers.Orders
  alias Edenflowers.Translations

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &populate/1)
  end

  defp populate(changeset) do
    variant_id = Ash.Changeset.get_attribute(changeset, :product_variant_id)

    with id when not is_nil(id) <- variant_id,
         {:ok, variant} <-
           Catalog.get_variant_by_id(id, load: [:photo_slug, product: [:tax_rate]], authorize?: false) do
      attrs = %{
        product_id: variant.product.id,
        product_name: product_name(variant.product, Ash.Changeset.get_attribute(changeset, :order_id)),
        product_image_slug: variant.photo_slug,
        unit_price: variant.price,
        tax_rate: variant.product.tax_rate.percentage,
        variant_size: variant.size,
        free_delivery: variant.product.free_delivery
      }

      Ash.Changeset.force_change_attributes(changeset, attrs)
    else
      _ ->
        Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
          field: :product_variant_id,
          message: ~t"is invalid"
        })
    end
  end

  # Named in the order's language, as receipts and emails show it as saved.
  defp product_name(product, order_id) do
    case Orders.get_order_by_id(order_id, authorize?: false) do
      {:ok, order} -> Translations.translate(product, String.to_existing_atom(order.locale)).name
      _ -> product.name
    end
  end
end
