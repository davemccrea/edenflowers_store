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
               |> Ash.create()

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
               |> Ash.create()

      assert size == :medium
      assert trackable == true
      assert quantity == 100
    end

    test "fails to create product variant without product_id" do
      params = %{
        price: Decimal.new("10.99"),
        image_slug: "image.jpg"
      }

      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.Required{field: :product_id}]}} =
               ProductVariant
               |> Ash.Changeset.for_create(:create, params)
               |> Ash.create()
    end

    test "fails to create product variant without price", %{product: product} do
      params = %{
        product_id: product.id,
        image_slug: "image.jpg"
      }

      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.Required{field: :price}]}} =
               ProductVariant
               |> Ash.Changeset.for_create(:create, params)
               |> Ash.create()
    end

    test "fails to create product variant without image", %{product: product} do
      params = %{
        product_id: product.id,
        price: Decimal.new("10.99")
      }

      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.Required{field: :image_slug}]}} =
               ProductVariant
               |> Ash.Changeset.for_create(:create, params)
               |> Ash.create()
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
               |> Ash.create()

      assert msg =~ "must be more than or equal to"
    end

    test "updates product variant price", %{product: product} do
      variant = generate(product_variant(product_id: product.id, price: Decimal.new("9.99")))

      new_price = Decimal.new("11.50")

      assert {:ok, %ProductVariant{price: updated_price}} =
               variant
               |> Ash.Changeset.for_update(:update, %{price: new_price})
               |> Ash.update()

      assert updated_price == new_price
    end

    test "updates product variant stock quantity", %{product: product} do
      variant = generate(product_variant(product_id: product.id, stock_quantity: 50))

      new_quantity = 75

      assert {:ok, %ProductVariant{stock_quantity: updated_quantity}} =
               variant
               |> Ash.Changeset.for_update(:update, %{stock_quantity: new_quantity})
               |> Ash.update()

      assert updated_quantity == new_quantity
    end

    test "fails to update product variant stock quantity to negative", %{product: product} do
      variant = generate(product_variant(product_id: product.id, stock_quantity: 50))

      new_quantity = -5

      assert {:error,
              %Ash.Error.Invalid{errors: [%Ash.Error.Changes.InvalidAttribute{field: :stock_quantity, message: msg}]}} =
               variant
               |> Ash.Changeset.for_update(:update, %{stock_quantity: new_quantity})
               |> Ash.update()

      assert msg =~ "must be more than or equal to"
    end

    test "destroys product variant", %{product: product} do
      variant = generate(product_variant(product_id: product.id))

      assert :ok = Ash.destroy!(variant)
      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} = Ash.get(ProductVariant, variant.id)
    end
  end
end
