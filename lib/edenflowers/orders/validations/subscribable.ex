defmodule Edenflowers.Orders.Validations.Subscribable do
  @moduledoc "A cart line can be a subscription only for a product that can be subscribed to."
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Catalog

  @impl true
  def validate(changeset, _opts, context) do
    variant_id = Ash.Changeset.get_attribute(changeset, :product_variant_id)

    if is_nil(Ash.Changeset.get_attribute(changeset, :interval_weeks)) or is_nil(variant_id) do
      :ok
    else
      case Catalog.get_variant_by_id(variant_id, Ash.Context.to_opts(context, load: [:product])) do
        {:ok, %{product: %{subscribable: false}}} ->
          {:error, field: :interval_weeks, message: ~t"This product can't be subscribed to"}

        # An unknown variant is PopulateFromVariant's to refuse.
        _subscribable_or_unknown ->
          :ok
      end
    end
  end
end
