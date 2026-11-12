defmodule Edenflowers.Catalog.Changes.MoveCategory do
  @moduledoc """
  Swaps a category with its neighbour in the store order, then numbers every
  category by its place. Renumbering all of them clears unset and duplicate
  positions, which would otherwise make a single step land somewhere else.
  """
  use Ash.Resource.Change

  alias Edenflowers.Catalog.ProductCategory

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      opts = Ash.Context.to_opts(context)
      categories = ProductCategory |> Ash.Query.for_read(:in_store_order) |> Ash.read!(opts)
      index = Enum.find_index(categories, &(&1.id == changeset.data.id))

      step = if Ash.Changeset.get_argument(changeset, :direction) == :up, do: -1, else: 1
      target = (index + step) |> max(0) |> min(length(categories) - 1)
      {moved, others} = List.pop_at(categories, index)

      others
      |> List.insert_at(target, moved)
      |> Enum.with_index()
      |> Enum.reject(fn {category, position} -> category.id == moved.id or category.position == position end)
      |> Enum.each(fn {category, position} -> Ash.update!(category, %{position: position}, opts) end)

      Ash.Changeset.force_change_attribute(changeset, :position, target)
    end)
  end
end
