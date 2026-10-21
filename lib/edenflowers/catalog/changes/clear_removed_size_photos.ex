defmodule Edenflowers.Catalog.Changes.ClearRemovedSizePhotos do
  @moduledoc """
  A size whose photo was removed from its product goes back to the main photo.
  The file stays on disk.
  """
  use Ash.Resource.Change
  require Ash.Query

  alias Edenflowers.Catalog.ProductVariant

  @impl true
  def change(changeset, _opts, _context) do
    if Ash.Changeset.changing_attribute?(changeset, :photo_slugs) do
      Ash.Changeset.after_action(changeset, fn _changeset, product ->
        ProductVariant
        |> Ash.Query.filter(product_id == ^product.id and own_photo_slug not in ^product.photo_slugs)
        |> Ash.bulk_update!(:update, %{own_photo_slug: nil}, authorize?: false, strategy: [:atomic, :stream])

        {:ok, product}
      end)
    else
      changeset
    end
  end
end
