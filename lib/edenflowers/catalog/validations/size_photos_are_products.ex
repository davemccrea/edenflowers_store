defmodule Edenflowers.Catalog.Validations.SizePhotosAreProducts do
  @moduledoc """
  A size submitted with its product may only pick one of that product's photos.
  Both are in this changeset, so the size never re-reads its product.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "admin"]

  @impl true
  def validate(changeset, _opts, _context) do
    photo_slugs = Ash.Changeset.get_attribute(changeset, :photo_slugs) || []

    errors =
      for {size, index} <- Enum.with_index(Ash.Changeset.get_argument(changeset, :product_variants) || []),
          slug = own_photo_slug(size),
          slug not in [nil, "" | photo_slugs] do
        Ash.Error.Changes.InvalidAttribute.exception(
          field: :own_photo_slug,
          path: [:product_variants, index],
          message: ~t"Must be one of the product's photos"
        )
      end

    if errors == [], do: :ok, else: {:error, errors}
  end

  # Forms submit string keys, code atom keys.
  defp own_photo_slug(size), do: Map.get(size, :own_photo_slug, Map.get(size, "own_photo_slug"))
end
