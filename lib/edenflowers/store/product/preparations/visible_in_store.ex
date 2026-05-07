defmodule Edenflowers.Store.Product.Preparations.VisibleInStore do
  use Ash.Resource.Preparation
  require Ash.Query

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def prepare(query, _opts, _context) do
    Ash.Query.filter(
      query,
      draft == false and
        exists(product_variants) and
        product_category.draft == false
    )
    |> Ash.Query.load([:cheapest_price, :product_variants, :product_category])
  end
end
