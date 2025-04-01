defmodule Edenflowers.Store.ProductVariantTest do
  use Edenflowers.DataCase
  import Edenflowers.Fixtures

  alias Edenflowers.Store.ProductVariant

  describe "ProductVariant Resource" do
    test "creates product variant with required fields" do
      tax_rate = fixture(:tax_rate)
      product = fixture(:product, tax_rate_id: tax_rate.id)

      params = %{
        product_id: product.id,
        price: Decimal.new("10.99"),
        image: "/images/variant1.jpg"
      }

      assert {:ok, %ProductVariant{price: price, image: image, product_id: product_id}} =
               ProductVariant
               |> Ash.Changeset.for_create(:create, params)
               |> Ash.create()

      assert price == Decimal.new("10.99")
      assert image == "/images/variant1.jpg"
      assert product_id == product.id
    end

    test "creates product variant with all fields" do
      tax_rate = fixture(:tax_rate)
      product = fixture(:product, tax_rate_id: tax_rate.id)

      params = %{
        product_id: product.id,
        price: Decimal.new("12.50"),
        image: "/images/variant_full.jpg",
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
        image: "/images/variant1.jpg"
      }

      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.Required{field: :product_id}]}} =
               ProductVariant
               |> Ash.Changeset.for_create(:create, params)
               |> Ash.create()
    end

    test "fails to create product variant without price" do
      tax_rate = fixture(:tax_rate)
      product = fixture(:product, tax_rate_id: tax_rate.id)

      params = %{
        product_id: product.id,
        image: "/images/variant1.jpg"
      }

      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.Required{field: :price}]}} =
               ProductVariant
               |> Ash.Changeset.for_create(:create, params)
               |> Ash.create()
    end

    test "fails to create product variant without image" do
      tax_rate = fixture(:tax_rate)
      product = fixture(:product, tax_rate_id: tax_rate.id)

      params = %{
        product_id: product.id,
        price: Decimal.new("10.99")
      }

      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.Required{field: :image}]}} =
               ProductVariant
               |> Ash.Changeset.for_create(:create, params)
               |> Ash.create()
    end

    test "fails to create product variant with negative stock_quantity" do
      tax_rate = fixture(:tax_rate)
      product = fixture(:product, tax_rate_id: tax_rate.id)

      params = %{
        product_id: product.id,
        price: Decimal.new("10.99"),
        image: "/images/variant1.jpg",
        stock_quantity: -10
      }

      assert {:error,
              %Ash.Error.Invalid{errors: [%Ash.Error.Changes.InvalidAttribute{field: :stock_quantity, message: msg}]}} =
               ProductVariant
               |> Ash.Changeset.for_create(:create, params)
               |> Ash.create()

      assert msg =~ "must be more than or equal to"
    end

    test "updates product variant price" do
      tax_rate = fixture(:tax_rate)
      product = fixture(:product, tax_rate_id: tax_rate.id)
      variant = fixture(:product_variant, product_id: product.id, price: Decimal.new("9.99"))

      new_price = Decimal.new("11.50")

      assert {:ok, %ProductVariant{price: updated_price}} =
               variant
               |> Ash.Changeset.for_update(:update, %{price: new_price})
               |> Ash.update()

      assert updated_price == new_price
    end

    test "updates product variant stock quantity" do
      tax_rate = fixture(:tax_rate)
      product = fixture(:product, tax_rate_id: tax_rate.id)
      variant = fixture(:product_variant, product_id: product.id, stock_quantity: 50)

      new_quantity = 75

      assert {:ok, %ProductVariant{stock_quantity: updated_quantity}} =
               variant
               |> Ash.Changeset.for_update(:update, %{stock_quantity: new_quantity})
               |> Ash.update()

      assert updated_quantity == new_quantity
    end

    test "fails to update product variant stock quantity to negative" do
      tax_rate = fixture(:tax_rate)
      product = fixture(:product, tax_rate_id: tax_rate.id)
      variant = fixture(:product_variant, product_id: product.id, stock_quantity: 50)

      new_quantity = -5

      assert {:error,
              %Ash.Error.Invalid{errors: [%Ash.Error.Changes.InvalidAttribute{field: :stock_quantity, message: msg}]}} =
               variant
               |> Ash.Changeset.for_update(:update, %{stock_quantity: new_quantity})
               |> Ash.update()

      assert msg =~ "must be more than or equal to"
    end

    test "destroys product variant" do
      tax_rate = fixture(:tax_rate)
      product = fixture(:product, tax_rate_id: tax_rate.id)
      variant = fixture(:product_variant, product_id: product.id)

      assert :ok = Ash.destroy!(variant)
      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} = Ash.get(ProductVariant, variant.id)
    end
  end
end
