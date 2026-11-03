defmodule Edenflowers.Slug.SetSlug do
  @moduledoc """
  Gives a record the slug its page lives at, as Product and Course do.

  A record without one gets the slug typed in the form, or else one made from
  its English name, with -2, -3, … added if another record has or had it.
  Renaming keeps the slug. When Jennie edits the slug of a record that has one,
  a slug another record has or had is an error rather than quietly changed, and
  the old slug is remembered in `former_slugs` so links shared with it still
  work.

  Options:

    * `:former_slugs` - the resource remembering old slugs, with `slug` and an
      owner key such as `product_id`
    * `:owner_key` - that owner key
    * `:fallback` - the slug for a name with nothing URL-shaped in it, like
      only emoji
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Edenflowers.Slug

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.before_action(changeset, &set_slug(&1, opts))
  end

  defp set_slug(changeset, opts) do
    id = Ash.Changeset.get_attribute(changeset, :id)
    current = stored_slug(changeset, id)
    typed = changeset |> Ash.Changeset.get_attribute(:slug) |> Slug.slugify()

    cond do
      is_nil(current) ->
        from_name = Slug.slugify(Ash.Changeset.get_attribute(changeset, :name))
        base = Enum.find([typed, from_name], opts[:fallback], &(&1 != ""))
        slug = Slug.unique(base, &taken?(changeset.resource, &1, id, opts))
        Ash.Changeset.force_change_attribute(changeset, :slug, slug)

      # An unchanged form field may still contain the slug from before another tab edited it.
      typed == changeset.data.slug or typed == current ->
        Ash.Changeset.force_change_attribute(changeset, :slug, current)

      typed == "" ->
        Ash.Changeset.add_error(changeset, field: :slug, message: "can't be blank")

      taken?(changeset.resource, typed, id, opts) ->
        Ash.Changeset.add_error(changeset, field: :slug, message: "is already taken")

      true ->
        changeset
        |> Ash.Changeset.force_change_attribute(:slug, typed)
        |> Ash.Changeset.after_action(fn _changeset, record -> remember(record, current, opts) end)
    end
  end

  # Read afresh rather than from the form's copy, which is stale if the slug
  # changed in another tab since the form opened.
  defp stored_slug(%{action_type: :create}, _id), do: nil

  defp stored_slug(changeset, id) do
    case Ash.get(changeset.resource, id, authorize?: false) do
      {:ok, record} -> record.slug
      {:error, _} -> nil
    end
  end

  defp remember(record, former_slug, opts) do
    owner_key = opts[:owner_key]

    # Taking back one of its own former slugs makes it current again.
    opts[:former_slugs]
    |> Ash.Query.filter_input([{owner_key, record.id}, slug: record.slug])
    |> Ash.bulk_destroy!(:destroy, %{}, authorize?: false)

    Ash.create!(opts[:former_slugs], %{:slug => former_slug, owner_key => record.id},
      action: :create,
      authorize?: false
    )

    {:ok, record}
  end

  defp taken?(resource, slug, id, opts) do
    resource |> Ash.Query.filter(slug == ^slug and id != ^id) |> Ash.exists?(authorize?: false) or
      opts[:former_slugs]
      |> Ash.Query.filter_input(slug: slug)
      |> Ash.read!(authorize?: false)
      |> Enum.any?(&(Map.fetch!(&1, opts[:owner_key]) != id))
  end
end
