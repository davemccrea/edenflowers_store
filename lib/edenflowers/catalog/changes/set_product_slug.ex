defmodule Edenflowers.Catalog.Changes.SetProductSlug do
  @moduledoc """
  Gives a product the slug its page lives at.

  A product without one gets the slug typed in the form, or else one made from
  its English name, with -2, -3, … added if another product has or had it.
  Renaming a product keeps its slug. When Jennie edits the slug of a product
  that has one, a slug another product has or had is an error rather than
  quietly changed, and the old slug becomes a `FormerProductSlug` so links
  shared with it still work.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Edenflowers.Catalog.FormerProductSlug
  alias Edenflowers.Catalog.Product
  alias Edenflowers.Slug

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &set_slug/1)
  end

  defp set_slug(changeset) do
    product_id = Ash.Changeset.get_attribute(changeset, :id)
    current = changeset.data.slug
    typed = changeset |> Ash.Changeset.get_attribute(:slug) |> Slug.slugify()

    cond do
      is_nil(current) ->
        from_name = Slug.slugify(Ash.Changeset.get_attribute(changeset, :name))
        # A name of only emoji or punctuation leaves nothing to build a slug from.
        base = Enum.find([typed, from_name], "product", &(&1 != ""))
        slug = Slug.unique(base, &taken?(&1, product_id))
        Ash.Changeset.force_change_attribute(changeset, :slug, slug)

      typed == current ->
        Ash.Changeset.force_change_attribute(changeset, :slug, current)

      typed == "" ->
        Ash.Changeset.add_error(changeset, field: :slug, message: "can't be blank")

      taken?(typed, product_id) ->
        Ash.Changeset.add_error(changeset, field: :slug, message: "is already used by another product")

      true ->
        changeset
        |> Ash.Changeset.force_change_attribute(:slug, typed)
        |> Ash.Changeset.after_action(fn _changeset, product -> remember(product, current) end)
    end
  end

  defp remember(product, former_slug) do
    # Taking back one of its own former slugs makes it current again.
    FormerProductSlug
    |> Ash.Query.filter(product_id == ^product.id and slug == ^product.slug)
    |> Ash.bulk_destroy!(:destroy, %{}, authorize?: false)

    Ash.create!(FormerProductSlug, %{slug: former_slug, product_id: product.id}, action: :create, authorize?: false)
    {:ok, product}
  end

  defp taken?(slug, product_id) do
    Product |> Ash.Query.filter(slug == ^slug and id != ^product_id) |> Ash.exists?(authorize?: false) or
      FormerProductSlug
      |> Ash.Query.filter(slug == ^slug and product_id != ^product_id)
      |> Ash.exists?(authorize?: false)
  end
end
