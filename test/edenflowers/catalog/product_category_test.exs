defmodule Edenflowers.Catalog.ProductCategoryTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Catalog

  test "a public category is found by its slug" do
    bouquets = generate(product_category(slug: "bouquets", visibility: :public))
    generate(product_category(slug: "secret", visibility: :hidden))

    assert {:ok, %{id: id}} = Catalog.get_category_by_slug("bouquets")
    assert id == bouquets.id
    assert {:error, _} = Catalog.get_category_by_slug("secret")
  end
end
