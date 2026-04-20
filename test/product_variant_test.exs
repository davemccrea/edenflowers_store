defmodule Edenflowers.Store.ProductVariantTest do
  use Edenflowers.DataCase
  import Generator
  alias Edenflowers.Store.ProductVariant

  setup do
    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    {:ok, tax_rate: tax_rate, product: product}
  end

  describe "ProductVariant Resource" do
    test "creates product variant with required fields", %{product: product} do
      params = %{
        product_id: product.id,
        price: Decimal.new("10.99"),
        image_slug: "image.jpg"
      }

      assert {:ok, %ProductVariant{price: price, image_slug: image_slug, product_id: product_id}} =
               ProductVariant
               |> Ash.Changeset.for_create(:create, params)
               |> Ash.create(authorize?: false)

      assert price == Decimal.new("10.99")
      assert image_slug == "image.jpg"
      assert product_id == product.id
    end

    test "creates product variant with all fields", %{product: product} do
      params = %{
        product_id: product.id,
        price: Decimal.new("12.50"),
        image_slug: "image.jpg",
        size: :medium,
        stock_trackable: true,
        stock_quantity: 100
      }

      assert {:ok, %ProductVariant{size: size, stock_trackable: trackable, stock_quantity: quantity}} =
               ProductVariant
               |> Ash.Changeset.for_create(:create, params)
               |> Ash.create(authorize?: false)

      assert size == :medium
      assert trackable == true
      assert quantity == 100
    end

    test "fails to create product variant with negative stock_quantity", %{product: product} do
      params = %{
        product_id: product.id,
        price: Decimal.new("10.99"),
        image_slug: "image.jpg",
        stock_quantity: -10
      }

      assert {:error,
              %Ash.Error.Invalid{errors: [%Ash.Error.Changes.InvalidAttribute{field: :stock_quantity, message: msg}]}} =
               ProductVariant
               |> Ash.Changeset.for_create(:create, params)
               |> Ash.create(authorize?: false)

      assert msg =~ "must be greater than or equal to"
    end

    test "updates product variant price", %{product: product} do
      variant = generate(product_variant(product_id: product.id, price: Decimal.new("9.99")))

      new_price = Decimal.new("11.50")

      assert {:ok, %ProductVariant{price: updated_price}} =
               variant
               |> Ash.Changeset.for_update(:update, %{price: new_price})
               |> Ash.update(authorize?: false)

      assert updated_price == new_price
    end

    test "updates product variant stock quantity", %{product: product} do
      variant = generate(product_variant(product_id: product.id, stock_quantity: 50))

      new_quantity = 75

      assert {:ok, %ProductVariant{stock_quantity: updated_quantity}} =
               variant
               |> Ash.Changeset.for_update(:update, %{stock_quantity: new_quantity})
               |> Ash.update(authorize?: false)

      assert updated_quantity == new_quantity
    end

    test "fails to update product variant stock quantity to negative", %{product: product} do
      variant = generate(product_variant(product_id: product.id, stock_quantity: 50))

      new_quantity = -5

      assert {:error,
              %Ash.Error.Invalid{errors: [%Ash.Error.Changes.InvalidAttribute{field: :stock_quantity, message: msg}]}} =
               variant
               |> Ash.Changeset.for_update(:update, %{stock_quantity: new_quantity})
               |> Ash.update(authorize?: false)

      assert msg =~ "must be greater than or equal to"
    end

    test "destroys product variant", %{product: product} do
      variant = generate(product_variant(product_id: product.id))

      assert :ok = Ash.destroy!(variant, authorize?: false)
      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} = Ash.get(ProductVariant, variant.id)
    end
  end

  describe "ProductVariant.for_card_drawer" do
    setup do
      tax_rate = generate(tax_rate())
      cards_category = generate(product_category(slug: "cards", draft: false))
      draft_cards_category = generate(product_category(slug: "cards-draft", draft: true))
      other_category = generate(product_category(draft: false))

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

    test "returns variants from the cards category", %{card_product: card_product} do
      variant = generate(product_variant(product_id: card_product.id, draft: false))

      variants = ProductVariant.for_card_drawer!(authorize?: false)

      assert Enum.any?(variants, fn v -> v.id == variant.id end)
    end

    test "excludes variants from other categories", %{card_product: card_product, other_product: other_product} do
      card_variant = generate(product_variant(product_id: card_product.id, draft: false))
      other_variant = generate(product_variant(product_id: other_product.id, draft: false))

      variants = ProductVariant.for_card_drawer!(authorize?: false)

      assert Enum.any?(variants, fn v -> v.id == card_variant.id end)
      refute Enum.any?(variants, fn v -> v.id == other_variant.id end)
    end

    test "excludes draft variants", %{card_product: card_product} do
      draft_variant = generate(product_variant(product_id: card_product.id, draft: true))

      variants = ProductVariant.for_card_drawer!(authorize?: false)

      refute Enum.any?(variants, fn v -> v.id == draft_variant.id end)
    end

    test "excludes variants of draft products", %{tax_rate: tax_rate, cards_category: cards_category} do
      draft_product = generate(product(tax_rate_id: tax_rate.id, product_category_id: cards_category.id, draft: true))
      variant = generate(product_variant(product_id: draft_product.id, draft: false))

      variants = ProductVariant.for_card_drawer!(authorize?: false)

      refute Enum.any?(variants, fn v -> v.id == variant.id end)
    end

    test "excludes variants whose product category is draft", %{tax_rate: tax_rate, draft_cards_category: draft_cards_category} do
      product = generate(product(tax_rate_id: tax_rate.id, product_category_id: draft_cards_category.id, draft: false))
      variant = generate(product_variant(product_id: product.id, draft: false))

      variants = ProductVariant.for_card_drawer!(authorize?: false)

      refute Enum.any?(variants, fn v -> v.id == variant.id end)
    end

    test "loads product with tax_rate", %{card_product: card_product} do
      generate(product_variant(product_id: card_product.id, draft: false))

      variants = ProductVariant.for_card_drawer!(authorize?: false)
      found = Enum.find(variants, fn v -> v.product_id == card_product.id end)

      assert found != nil
      assert found.product.id == card_product.id
      assert found.product.tax_rate != nil
    end

    test "results are sorted by size ascending", %{card_product: card_product} do
      generate(product_variant(product_id: card_product.id, size: :large, draft: false))
      generate(product_variant(product_id: card_product.id, size: :small, draft: false))
      generate(product_variant(product_id: card_product.id, size: :medium, draft: false))

      variants =
        ProductVariant.for_card_drawer!(authorize?: false)
        |> Enum.filter(fn v -> v.product_id == card_product.id end)
        |> Enum.map(& &1.size)

      assert variants == Enum.sort(variants)
    end
  end
end
