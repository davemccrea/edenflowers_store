defmodule Edenflowers.Catalog.Changes.TidyHiddenPhotos do
  @moduledoc """
  Keeps a product's hidden photos among its photos, and never hides the main
  photo, so removing a photo or making a hidden one main needs no extra step.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    others = changeset |> Ash.Changeset.get_attribute(:photo_slugs) |> List.wrap() |> Enum.drop(1)
    hidden = Ash.Changeset.get_attribute(changeset, :hidden_photo_slugs) || []

    Ash.Changeset.force_change_attribute(changeset, :hidden_photo_slugs, Enum.filter(hidden, &(&1 in others)))
  end
end
