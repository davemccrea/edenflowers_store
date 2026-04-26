defmodule Edenflowers.Store.LineItem.Changes.PopulateFromVariant do
  @moduledoc """
  Loads the product variant referenced by `:product_variant_id` and
  derives the line item's denormalized snapshot fields from it server-side.

  This prevents clients from supplying their own `unit_price`, `tax_rate`,
  `product_id`, `product_name`, or `product_image_slug` — values that must
  reflect the canonical product/variant record, not user input.

  Pass `card_size?: true` for actions that should also derive `:card_size`
  from the variant.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Store.ProductVariant

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, opts, _context) do
    with id when not is_nil(id) <- Ash.Changeset.get_attribute(changeset, :product_variant_id),
         {:ok, variant} <-
           Ash.get(ProductVariant, id, load: [product: [:tax_rate]], authorize?: false) do
      Ash.Changeset.force_change_attributes(changeset, attrs_from_variant(variant, opts))
    else
      nil ->
        # Required-attribute validation handles the missing-id case downstream.
        changeset

      {:error, _} ->
        Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
          field: :product_variant_id,
          message: ~t"Product variant not found"
        })
    end
  end

  defp attrs_from_variant(variant, opts) do
    base = %{
      unit_price: variant.price,
      tax_rate: variant.product.tax_rate.percentage,
      product_id: variant.product.id,
      product_name: variant.product.name,
      product_image_slug: variant.image_slug
    }

    if opts[:card_size?] == true, do: Map.put(base, :card_size, variant.size), else: base
  end
end
