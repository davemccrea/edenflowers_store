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
               |> Ash.create()
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
               |> Ash.create()
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
               |> Ash.create()

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
               |> Ash.create()
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
               |> Ash.create()
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
end
