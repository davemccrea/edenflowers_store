defmodule Edenflowers.Catalog.ProductCategoryTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Catalog

  test "a category is found by its slug in a locale, falling back to the English slug" do
    bouquets =
      generate(
        product_category(
          slug: "bouquets",
          visibility: :public,
          translations: %{fi: %{name: "Kukkakimput", slug: "kukkakimput"}}
        )
      )

    assert {:ok, %{id: id}} = Catalog.get_category_by_slug("kukkakimput", :fi)
    assert id == bouquets.id
    assert {:error, _} = Catalog.get_category_by_slug("bouquets", :fi)
    assert {:ok, _} = Catalog.get_category_by_slug("bouquets", :"sv-FI")
    assert {:ok, _} = Catalog.get_category_by_slug("bouquets", :"en-GB")
    assert {:error, _} = Catalog.get_category_by_slug("kukkakimput", :"en-GB")
  end
end
