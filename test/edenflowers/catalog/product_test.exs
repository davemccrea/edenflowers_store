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

    test "carries each product's cheapest price", %{tax_rate: tax_rate} do
      published_category = generate(product_category(visibility: :public))
      product = generate(product(tax_rate_id: tax_rate.id, product_category_id: published_category.id, draft: false))
      generate(product_variant(product_id: product.id, price: "24.00"))
      generate(product_variant(product_id: product.id, price: "15.99"))

      products = Catalog.list_store_products!(authorize?: false)
      found_product = Enum.find(products, fn p -> p.id == product.id end)

      assert Decimal.equal?(found_product.cheapest_price, "15.99")
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

  describe "a product's photos" do
    test "must number 1 to 8" do
      for photo_slugs <- [[], Enum.map(1..9, &"#{&1}.jpg")] do
        assert {:error, %Ash.Error.Invalid{errors: [%{field: :photo_slugs}]}} =
                 update(generate(product()), %{photo_slugs: photo_slugs})
      end
    end

    test "the first is the main photo, which a size without its own follows" do
      product = generate(product(photo_slugs: ["a.jpg", "b.jpg"]))
      generate(product_variant(product_id: product.id))

      product = update!(product, %{photo_slugs: ["b.jpg", "a.jpg"]})

      assert [%{photo_slug: "b.jpg"}] =
               Ash.load!(product, [:main_photo_slug, product_variants: [:photo_slug]]).product_variants

      assert Ash.load!(product, :main_photo_slug).main_photo_slug == "b.jpg"
    end

    test "a size can only pick one of its product's photos" do
      product = generate(product(photo_slugs: ["a.jpg", "b.jpg"]))
      variant = generate(product_variant(product_id: product.id))

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :own_photo_slug, path: [:product_variants, 0]}]}} =
               update(product, %{product_variants: [%{id: variant.id, own_photo_slug: "c.jpg"}]})

      product = update!(product, %{product_variants: [%{id: variant.id, own_photo_slug: "b.jpg"}]})

      assert [%{own_photo_slug: "b.jpg"}] = Ash.load!(product, :product_variants).product_variants
    end

    test "removing the photo a size uses sends it back to the main photo" do
      product = generate(product(photo_slugs: ["a.jpg", "b.jpg"]))
      keeps = generate(product_variant(product_id: product.id, own_photo_slug: "a.jpg"))
      loses = generate(product_variant(product_id: product.id, own_photo_slug: "b.jpg"))

      update!(product, %{photo_slugs: ["a.jpg"]})

      assert Ash.get!(Catalog.ProductVariant, keeps.id, authorize?: false).own_photo_slug == "a.jpg"
      assert Ash.get!(Catalog.ProductVariant, loses.id, authorize?: false, load: [:photo_slug]).photo_slug == "a.jpg"
    end

    test "hidden photos stay among its photos and never include the main one" do
      product = generate(product(photo_slugs: ["a.jpg", "b.jpg", "c.jpg"]))

      assert update!(product, %{hidden_photo_slugs: ["a.jpg", "b.jpg", "z.jpg"]}).hidden_photo_slugs == ["b.jpg"]

      product = update!(product, %{hidden_photo_slugs: ["b.jpg", "c.jpg"]})
      product = update!(product, %{photo_slugs: ["b.jpg", "a.jpg"]})
      assert product.hidden_photo_slugs == []
    end
  end

  defp update(product, params),
    do: product |> Ash.Changeset.for_update(:update, params) |> Ash.update(authorize?: false)

  defp update!(product, params),
    do: product |> Ash.Changeset.for_update(:update, params) |> Ash.update!(authorize?: false)
end
