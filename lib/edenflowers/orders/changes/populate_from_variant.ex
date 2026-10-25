defmodule Edenflowers.Orders.Changes.PopulateFromVariant do
  @moduledoc """
  Copies a catalogue variant's product, price, and tax details onto a new line item.
  """

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
    locale = order_locale(Ash.Changeset.get_attribute(changeset, :order_id))

    case snapshot(variant_id, locale) do
      {:ok, attrs} ->
        Ash.Changeset.force_change_attributes(changeset, attrs)

      :error ->
        Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
          field: :product_variant_id,
          message: ~t"is invalid"
        })
    end
  end

  @doc """
  What a line for `variant_id` copies from it, the product named in `locale`
  as receipts and emails show it once saved. A nil locale keeps the product's
  own name.
  """
  def snapshot(nil, _locale), do: :error

  def snapshot(variant_id, locale) do
    case Catalog.get_variant_by_id(variant_id, load: [:photo_slug, product: [:tax_rate]], authorize?: false) do
      {:ok, variant} ->
        {:ok,
         %{
           product_id: variant.product.id,
           product_name: product_name(variant.product, locale),
           product_image_slug: variant.photo_slug,
           unit_price: variant.price,
           tax_rate: variant.product.tax_rate.percentage,
           variant_size: variant.size,
           free_delivery: variant.product.free_delivery
         }}

      _ ->
        :error
    end
  end

  defp order_locale(order_id) do
    case Orders.get_order_by_id(order_id, authorize?: false) do
      {:ok, order} -> order.locale
      _ -> nil
    end
  end

  defp product_name(product, nil), do: product.name
  defp product_name(product, locale), do: Translations.translate(product, String.to_existing_atom(locale)).name
end
