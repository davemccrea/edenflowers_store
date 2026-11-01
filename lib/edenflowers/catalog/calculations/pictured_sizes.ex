defmodule Edenflowers.Catalog.Calculations.PicturedSizes do
  @moduledoc """
  Which size each of a product's photos shows, as a map from photo slug to size.

  A size's own photo shows that size. The main photo shows Medium, as Jennie
  always photographs Medium for it, so long as the product has a Medium size
  and no other size claims it. A photo two sizes share, or any other photo
  (a close-up, say), is left out: its size isn't known.
  """
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:main_photo_slug, product_variants: [:size, :own_photo_slug]]

  @impl true
  def calculate(records, _opts, _context), do: Enum.map(records, &pictured_sizes/1)

  defp pictured_sizes(product) do
    sizes = Enum.map(product.product_variants, & &1.size)

    main =
      if :medium in sizes and product.main_photo_slug,
        do: %{product.main_photo_slug => :medium},
        else: %{}

    own =
      product.product_variants
      |> Enum.filter(&(&1.own_photo_slug && &1.size))
      |> Enum.group_by(& &1.own_photo_slug, & &1.size)
      |> Enum.flat_map(fn
        {slug, [size]} -> [{slug, size}]
        _shared -> []
      end)
      |> Map.new()

    Map.merge(main, own)
  end
end
