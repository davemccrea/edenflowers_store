defmodule Edenflowers.Catalog.ProductVariantTest do
  use Edenflowers.DataCase, async: true
  import Generator
  alias Edenflowers.Catalog

  setup do
    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    {:ok, tax_rate: tax_rate, product: product}
  end

  describe "a product's sold_out?" do
    defp sold_out?(product), do: Ash.load!(product, :sold_out?, authorize?: false).sold_out?

    test "is true only when every size is tracked and at 0", %{product: product} do
      refute sold_out?(product)

      generate(product_variant(product_id: product.id, size: :small, stock_quantity: 0))
      assert sold_out?(product)

      generate(product_variant(product_id: product.id, size: :large))
      refute sold_out?(product)
    end
  end

  describe "Catalog.list_card_drawer_variants" do
    setup do
      tax_rate = generate(tax_rate())
      cards_category = generate(product_category(slug: "cards", visibility: :public))
      draft_cards_category = generate(product_category(slug: "cards-draft", visibility: :draft))
      other_category = generate(product_category(visibility: :public))

      card_product = generate(product(tax_rate_id: tax_rate.id, product_category_id: cards_category.id, draft: false))
      other_product = generate(product(tax_rate_id: tax_rate.id, product_category_id: other_category.id, draft: false))

      %{
        tax_rate: tax_rate,
        cards_category: cards_category,
        draft_cards_category: draft_cards_category,
        other_category: other_category,
        card_product: card_product,
        other_product: other_product
      }
    end

    test "excludes variants from other categories", %{card_product: card_product, other_product: other_product} do
      card_variant = generate(product_variant(product_id: card_product.id, draft: false))
      other_variant = generate(product_variant(product_id: other_product.id, draft: false))

      variants = Catalog.list_card_drawer_variants!(authorize?: false)

      assert Enum.any?(variants, fn v -> v.id == card_variant.id end)
      refute Enum.any?(variants, fn v -> v.id == other_variant.id end)
    end

    test "excludes sold-out variants", %{card_product: card_product} do
      sold_out = generate(product_variant(product_id: card_product.id, draft: false, stock_quantity: 0))
      in_stock = generate(product_variant(product_id: card_product.id, draft: false, stock_quantity: 1))

      ids = Enum.map(Catalog.list_card_drawer_variants!(authorize?: false), & &1.id)

      assert in_stock.id in ids
      refute sold_out.id in ids
    end

    test "excludes draft variants", %{card_product: card_product} do
      draft_variant = generate(product_variant(product_id: card_product.id, draft: true))

      variants = Catalog.list_card_drawer_variants!(authorize?: false)

      refute Enum.any?(variants, fn v -> v.id == draft_variant.id end)
    end

    test "excludes variants of draft products", %{tax_rate: tax_rate, cards_category: cards_category} do
      draft_product = generate(product(tax_rate_id: tax_rate.id, product_category_id: cards_category.id, draft: true))
      variant = generate(product_variant(product_id: draft_product.id, draft: false))

      variants = Catalog.list_card_drawer_variants!(authorize?: false)

      refute Enum.any?(variants, fn v -> v.id == variant.id end)
    end

    test "excludes variants whose product category is draft", %{
      tax_rate: tax_rate,
      draft_cards_category: draft_cards_category
    } do
      product = generate(product(tax_rate_id: tax_rate.id, product_category_id: draft_cards_category.id, draft: false))
      variant = generate(product_variant(product_id: product.id, draft: false))

      variants = Catalog.list_card_drawer_variants!(authorize?: false)

      refute Enum.any?(variants, fn v -> v.id == variant.id end)
    end

    test "loads product with tax_rate", %{card_product: card_product} do
      generate(product_variant(product_id: card_product.id, draft: false))

      variants = Catalog.list_card_drawer_variants!(authorize?: false)
      found = Enum.find(variants, fn v -> v.product_id == card_product.id end)

      assert found != nil
      assert found.product.id == card_product.id
      assert found.product.tax_rate != nil
    end
  end
end
