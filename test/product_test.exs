defmodule Edenflowers.Store.ProductTest do
  use Edenflowers.DataCase
  import Generator

  alias Edenflowers.Store.Product

  setup do
    tax_rate = generate(tax_rate())
    product_category = generate(product_category())
    {:ok, tax_rate: tax_rate, product_category: product_category}
  end

  describe "Product Resource" do
    test "fails to create product without tax_rate", %{product_category: product_category} do
      assert {:error, _} =
               Product
               |> Ash.Changeset.for_create(:create, %{
                 name: "Product 1",
                 description: "Product 1 description",
                 product_category_id: product_category.id
               })
               |> Ash.create(authorize?: false)
    end

    test "creates product when tax_rate is assigned", %{tax_rate: tax_rate, product_category: product_category} do
      assert {:ok, _} =
               Product
               |> Ash.Changeset.for_create(:create, %{
                 name: "Product 1",
                 description: "Product 1 description",
                 image_slug: "image.jpg",
                 tax_rate_id: tax_rate.id,
                 product_category_id: product_category.id
               })
               |> Ash.create(authorize?: false)
    end

    test "fails to create product if product name is not unique", %{
      tax_rate: tax_rate,
      product_category: product_category
    } do
      name = "Product 1"
      _product = generate(product(tax_rate_id: tax_rate.id, name: name, product_category_id: product_category.id))

      assert {:error, error} =
               Product
               |> Ash.Changeset.for_create(:create, %{
                 name: name,
                 description: "Product 1 description",
                 image_slug: "image.jpg",
                 tax_rate_id: tax_rate.id,
                 product_category_id: product_category.id
               })
               |> Ash.create(authorize?: false)

      assert %Ash.Error.Invalid{
               errors: [
                 %Ash.Error.Changes.InvalidAttribute{
                   field: :name,
                   message: "has already been taken"
                 }
               ]
             } = error
    end

    test "assigns fulfillment option to product", %{tax_rate: tax_rate, product_category: product_category} do
      fulfillment_option = generate(fulfillment_option(tax_rate_id: tax_rate.id))
      fulfillment_option_id = fulfillment_option.id

      assert {:ok, %{fulfillment_options: [%{id: ^fulfillment_option_id}]} = _} =
               Product
               |> Ash.Changeset.for_create(:create, %{
                 name: "Product 1",
                 description: "Product 1 description",
                 image_slug: "image.jpg",
                 tax_rate_id: tax_rate.id,
                 product_category_id: product_category.id,
                 fulfillment_option_ids: [fulfillment_option_id]
               })
               |> Ash.create(authorize?: false)
    end

    test "fails to assign fulfillment option to product if fulfillment option does not exist", %{tax_rate: tax_rate} do
      # Non existing resource
      id = Ecto.UUID.generate()

      assert {:error, _} =
               Product
               |> Ash.Changeset.for_create(:create, %{
                 tax_rate_id: tax_rate.id,
                 name: "Product 1",
                 description: "Product 1 description",
                 image_slug: "image.jpg",
                 fulfillment_option_ids: [id]
               })
               |> Ash.create(authorize?: false)
    end

    test "returns nil cheapest_price when product has no variants", %{tax_rate: tax_rate} do
      product = generate(product(tax_rate_id: tax_rate.id))

      loaded_product =
        Product
        |> Ash.get!(product.id)
        |> Ash.load!([:cheapest_price])

      assert loaded_product.cheapest_price == nil
    end

    test "returns correct cheapest_price with one variant", %{tax_rate: tax_rate} do
      product = generate(product(tax_rate_id: tax_rate.id))
      price = Decimal.new("15.99")
      _variant = generate(product_variant(product_id: product.id, price: price))

      loaded_product = Product |> Ash.get!(product.id) |> Ash.load!([:cheapest_price])

      assert loaded_product.cheapest_price == price
    end

    test "returns correct cheapest_price with multiple variants", %{tax_rate: tax_rate} do
      product = generate(product(tax_rate_id: tax_rate.id))
      price1 = Decimal.new("18.50")
      # Cheapest
      price2 = Decimal.new("12.00")
      price3 = Decimal.new("20.00")
      _variant1 = generate(product_variant(product_id: product.id, price: price1))
      _variant2 = generate(product_variant(product_id: product.id, price: price2))
      _variant3 = generate(product_variant(product_id: product.id, price: price3))

      loaded_product =
        Product
        |> Ash.get!(product.id)
        |> Ash.load!([:cheapest_price])

      assert loaded_product.cheapest_price == price2
    end
  end

  describe "Product.get_all_for_store filtering" do
    test "includes published products with variants and published category", %{tax_rate: tax_rate} do
      # Create published category
      published_category = generate(product_category(draft: false))

      # Create published product with variants
      product = generate(product(tax_rate_id: tax_rate.id, product_category_id: published_category.id, draft: false))
      _variant = generate(product_variant(product_id: product.id))

      products = Product.get_all_for_store!(authorize?: false)

      assert Enum.any?(products, fn p -> p.id == product.id end)
    end

    test "excludes draft products", %{tax_rate: tax_rate} do
      published_category = generate(product_category(draft: false))

      # Create draft product with variants
      draft_product =
        generate(product(tax_rate_id: tax_rate.id, product_category_id: published_category.id, draft: true))

      _variant = generate(product_variant(product_id: draft_product.id))

      products = Product.get_all_for_store!(authorize?: false)

      refute Enum.any?(products, fn p -> p.id == draft_product.id end)
    end

    test "excludes products without product_variants", %{tax_rate: tax_rate} do
      published_category = generate(product_category(draft: false))

      # Create published product WITHOUT variants
      product_no_variants =
        generate(product(tax_rate_id: tax_rate.id, product_category_id: published_category.id, draft: false))

      products = Product.get_all_for_store!(authorize?: false)

      refute Enum.any?(products, fn p -> p.id == product_no_variants.id end)
    end

    test "excludes products with draft category", %{tax_rate: tax_rate} do
      # Create draft category
      draft_category = generate(product_category(draft: true))

      # Create published product with variants but draft category
      product = generate(product(tax_rate_id: tax_rate.id, product_category_id: draft_category.id, draft: false))
      _variant = generate(product_variant(product_id: product.id))

      products = Product.get_all_for_store!(authorize?: false)

      refute Enum.any?(products, fn p -> p.id == product.id end)
    end

    test "loads cheapest_price, product_variants, and product_category", %{tax_rate: tax_rate} do
      published_category = generate(product_category(draft: false))
      product = generate(product(tax_rate_id: tax_rate.id, product_category_id: published_category.id, draft: false))
      _variant = generate(product_variant(product_id: product.id, price: "15.99"))

      products = Product.get_all_for_store!(authorize?: false)
      found_product = Enum.find(products, fn p -> p.id == product.id end)

      assert found_product != nil
      assert Decimal.equal?(found_product.cheapest_price, "15.99")
      assert length(found_product.product_variants) > 0
      assert found_product.product_category.id == published_category.id
    end
  end

  describe "Product.get_by_category filtering" do
    test "returns only products in specified category", %{tax_rate: tax_rate} do
      category_a = generate(product_category(draft: false))
      category_b = generate(product_category(draft: false))

      product_a = generate(product(tax_rate_id: tax_rate.id, product_category_id: category_a.id, draft: false))
      _variant_a = generate(product_variant(product_id: product_a.id))

      product_b = generate(product(tax_rate_id: tax_rate.id, product_category_id: category_b.id, draft: false))
      _variant_b = generate(product_variant(product_id: product_b.id))

      products = Product.get_by_category!(category_a.id, authorize?: false)

      assert Enum.any?(products, fn p -> p.id == product_a.id end)
      refute Enum.any?(products, fn p -> p.id == product_b.id end)
    end

    test "excludes draft products within category", %{tax_rate: tax_rate} do
      category = generate(product_category(draft: false))

      draft_product = generate(product(tax_rate_id: tax_rate.id, product_category_id: category.id, draft: true))
      _variant = generate(product_variant(product_id: draft_product.id))

      products = Product.get_by_category!(category.id, authorize?: false)

      refute Enum.any?(products, fn p -> p.id == draft_product.id end)
    end

    test "excludes products without variants in category", %{tax_rate: tax_rate} do
      category = generate(product_category(draft: false))

      product_no_variants = generate(product(tax_rate_id: tax_rate.id, product_category_id: category.id, draft: false))

      products = Product.get_by_category!(category.id, authorize?: false)

      refute Enum.any?(products, fn p -> p.id == product_no_variants.id end)
    end

    test "excludes products when category is draft", %{tax_rate: tax_rate} do
      draft_category = generate(product_category(draft: true))

      product = generate(product(tax_rate_id: tax_rate.id, product_category_id: draft_category.id, draft: false))
      _variant = generate(product_variant(product_id: product.id))

      products = Product.get_by_category!(draft_category.id, authorize?: false)

      assert products == []
    end

    test "returns empty list when category has no qualifying products", %{tax_rate: _tax_rate} do
      empty_category = generate(product_category(draft: false))

      products = Product.get_by_category!(empty_category.id, authorize?: false)

      assert products == []
    end
  end
end
