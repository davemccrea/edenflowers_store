defmodule Edenflowers.Store.LineItemTest do
  use Edenflowers.DataCase
  import Edenflowers.Fixtures
  alias Edenflowers.Store.LineItem

  describe "Order Item Resource" do
    test "creates an order item" do
      order = fixture(:order)
      tax_rate = fixture(:tax_rate)
      product = fixture(:product, tax_rate_id: tax_rate.id)
      product_variant = fixture(:product_variant, product_id: product.id)

      assert {:ok, _} =
               LineItem
               |> Ash.Changeset.for_create(:create, %{
                 order_id: order.id,
                 product_variant_id: product_variant.id,
                 unit_price: product_variant.price,
                 tax_rate: tax_rate.percentage
               })
               |> Ash.create()
    end

    test "default quantity is 1" do
      order = fixture(:order)
      tax_rate = fixture(:tax_rate)
      product = fixture(:product, tax_rate_id: tax_rate.id)
      product_variant = fixture(:product_variant, product_id: product.id)

      line_item =
        LineItem
        |> Ash.Changeset.for_create(:create, %{
          order_id: order.id,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage
        })
        |> Ash.create!()

      assert line_item.quantity == 1
    end

    test "quantity can only be 1 or greater" do
      order = fixture(:order)
      tax_rate = fixture(:tax_rate)
      product = fixture(:product, tax_rate_id: tax_rate.id)
      product_variant = fixture(:product_variant, product_id: product.id)

      assert {:error, _} =
               LineItem
               |> Ash.Changeset.for_create(:create, %{
                 order_id: order.id,
                 quantity: 0,
                 product_variant_id: product_variant.id,
                 unit_price: product_variant.price,
                 tax_rate: tax_rate.percentage
               })
               |> Ash.create()
    end

    test "increments quantity" do
      order = fixture(:order)
      tax_rate = fixture(:tax_rate)
      product = fixture(:product, tax_rate_id: tax_rate.id)
      product_variant = fixture(:product_variant, product_id: product.id)

      line_item =
        LineItem
        |> Ash.Changeset.for_create(:create, %{
          order_id: order.id,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage
        })
        |> Ash.create!()
        |> Ash.Changeset.for_update(:increment_quantity)
        |> Ash.update!()

      assert line_item.quantity == 2
    end

    test "decrements quantity" do
      order = fixture(:order)
      tax_rate = fixture(:tax_rate)
      product = fixture(:product, tax_rate_id: tax_rate.id)
      product_variant = fixture(:product_variant, product_id: product.id)

      line_item =
        LineItem
        |> Ash.Changeset.for_create(:create, %{
          order_id: order.id,
          product_variant_id: product_variant.id,
          quantity: 3,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage
        })
        |> Ash.create!()
        |> Ash.Changeset.for_update(:decrement_quantity)
        |> Ash.update!()

      assert line_item.quantity == 2
    end

    test "decrements quantity no lower than 1" do
      order = fixture(:order)
      tax_rate = fixture(:tax_rate)
      product = fixture(:product, tax_rate_id: tax_rate.id)
      product_variant = fixture(:product_variant, product_id: product.id)

      line_item =
        LineItem
        |> Ash.Changeset.for_create(:create, %{
          order_id: order.id,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage
        })
        |> Ash.create!()
        |> Ash.Changeset.for_update(:decrement_quantity)
        |> Ash.update!()

      assert line_item.quantity == 1
    end

    test "promotion_applied? returns true if promotion applied to order" do
      promotion = fixture(:promotion, discount_percentage: "0.20")
      order = fixture(:order, promotion_id: promotion.id)
      tax_rate = fixture(:tax_rate)
      product = fixture(:product, tax_rate_id: tax_rate.id)
      product_variant = fixture(:product_variant, product_id: product.id)

      line_item =
        LineItem
        |> Ash.Changeset.for_create(:create, %{
          order_id: order.id,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage
        })
        |> Ash.create!()
        |> Ash.load!(:promotion_applied?)

      assert line_item.promotion_applied? == true
    end

    test "promotion_applied? returns false if no promotion applied to order" do
      order = fixture(:order)
      tax_rate = fixture(:tax_rate)
      product = fixture(:product, tax_rate_id: tax_rate.id)
      product_variant = fixture(:product_variant, product_id: product.id)

      line_item =
        LineItem
        |> Ash.Changeset.for_create(:create, %{
          order_id: order.id,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage
        })
        |> Ash.create!()
        |> Ash.load!(:promotion_applied?)

      assert line_item.promotion_applied? == false
    end
  end
end
