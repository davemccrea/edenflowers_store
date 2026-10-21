defmodule Edenflowers.Catalog.ProductTest do
  use Edenflowers.DataCase, async: true
  import Generator

  alias Edenflowers.Catalog

  setup do
    tax_rate = generate(tax_rate())
    product_category = generate(product_category())
    {:ok, tax_rate: tax_rate, product_category: product_category}
  end

  describe "Catalog.list_store_products filtering" do
    test "excludes products whose only size was removed", %{tax_rate: tax_rate} do
      published_category = generate(product_category(visibility: :public))
      product = generate(product(tax_rate_id: tax_rate.id, product_category_id: published_category.id, draft: false))
      variant = generate(product_variant(product_id: product.id))

      Ash.destroy!(variant, authorize?: false)

      products = Catalog.list_store_products!(authorize?: false)

      refute Enum.any?(products, fn p -> p.id == product.id end)
    end

    test "excludes draft products", %{tax_rate: tax_rate} do
      published_category = generate(product_category(visibility: :public))

      draft_product =
        generate(product(tax_rate_id: tax_rate.id, product_category_id: published_category.id, draft: true))

      _variant = generate(product_variant(product_id: draft_product.id))

      products = Catalog.list_store_products!(authorize?: false)

      refute Enum.any?(products, fn p -> p.id == draft_product.id end)
    end

    test "excludes products without product_variants", %{tax_rate: tax_rate} do
      published_category = generate(product_category(visibility: :public))

      product_no_variants =
        generate(product(tax_rate_id: tax_rate.id, product_category_id: published_category.id, draft: false))

      products = Catalog.list_store_products!(authorize?: false)

      refute Enum.any?(products, fn p -> p.id == product_no_variants.id end)
    end

    test "excludes products with draft category", %{tax_rate: tax_rate} do
      draft_category = generate(product_category(visibility: :draft))
      product = generate(product(tax_rate_id: tax_rate.id, product_category_id: draft_category.id, draft: false))
      _variant = generate(product_variant(product_id: product.id))

      products = Catalog.list_store_products!(authorize?: false)

      refute Enum.any?(products, fn p -> p.id == product.id end)
    end

    test "loads cheapest_price, product_variants, and product_category", %{tax_rate: tax_rate} do
      published_category = generate(product_category(visibility: :public))
      product = generate(product(tax_rate_id: tax_rate.id, product_category_id: published_category.id, draft: false))
      _variant = generate(product_variant(product_id: product.id, price: "15.99"))

      products = Catalog.list_store_products!(authorize?: false)
      found_product = Enum.find(products, fn p -> p.id == product.id end)

      assert found_product != nil
      assert Decimal.equal?(found_product.cheapest_price, "15.99")
      assert found_product.product_variants != []
      assert found_product.product_category.id == published_category.id
    end
  end

  describe "Catalog.list_products_by_category filtering" do
    test "returns only products in specified category", %{tax_rate: tax_rate} do
      category_a = generate(product_category(visibility: :public))
      category_b = generate(product_category(visibility: :public))

      product_a = generate(product(tax_rate_id: tax_rate.id, product_category_id: category_a.id, draft: false))
      _variant_a = generate(product_variant(product_id: product_a.id))

      product_b = generate(product(tax_rate_id: tax_rate.id, product_category_id: category_b.id, draft: false))
      _variant_b = generate(product_variant(product_id: product_b.id))

      products = Catalog.list_products_by_category!(category_a.id, authorize?: false)

      assert Enum.any?(products, fn p -> p.id == product_a.id end)
      refute Enum.any?(products, fn p -> p.id == product_b.id end)
    end

    test "returns empty list when category has no qualifying products", %{tax_rate: _tax_rate} do
      empty_category = generate(product_category(visibility: :public))

      products = Catalog.list_products_by_category!(empty_category.id, authorize?: false)

      assert products == []
    end

    test "lists products by position, then name", %{tax_rate: tax_rate} do
      category = generate(product_category(visibility: :public))

      for {name, position} <- [{"A", nil}, {"B", 1}, {"C", 0}] do
        product =
          generate(
            product(
              name: name,
              position: position,
              tax_rate_id: tax_rate.id,
              product_category_id: category.id,
              draft: false
            )
          )

        generate(product_variant(product_id: product.id))
      end

      products = Catalog.list_products_by_category!(category.id, authorize?: false)

      assert Enum.map(products, & &1.name) == ["C", "B", "A"]
    end
  end
end
