defmodule Edenflowers.Catalog.Preparations.VisibleInStore do
  @moduledoc """
  Limits storefront reads to published products in public categories with at
  least one active variant. Sold-out products still appear and are marked by
  the loaded `sold_out?` calculation.
  """

  use Ash.Resource.Preparation
  require Ash.Query

  @impl true
  def prepare(query, _opts, _context) do
    Ash.Query.filter(
      query,
      draft == false and
        exists(product_variants) and
        product_category.visibility == :public
    )
    |> Ash.Query.load([:main_photo_slug, :cheapest_price, :sold_out?, :product_variants, :product_category])
  end
end
