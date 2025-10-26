defmodule Edenflowers.Store.LineItemTest do
  use Edenflowers.DataCase
  import Generator
  alias Edenflowers.Store.{Order, LineItem}

  setup do
    order = generate(order())
    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    product_variant = generate(product_variant(product_id: product.id))

    {:ok, order: order, tax_rate: tax_rate, product: product, product_variant: product_variant}
  end

  describe "Order Item Resource" do
    test "creates an order item", %{
      order: order,
      tax_rate: tax_rate,
      product: product,
      product_variant: product_variant
    } do
      assert {:ok, _} =
               LineItem
               |> Ash.Changeset.for_create(:create, %{
                 order_id: order.id,
                 product_id: product.id,
                 product_name: product.name,
                 product_image_slug: product.image_slug,
                 product_variant_id: product_variant.id,
                 unit_price: product_variant.price,
                 tax_rate: tax_rate.percentage
               })
               |> Ash.create(authorize?: false)
    end

    test "default quantity is 1", %{
      order: order,
      tax_rate: tax_rate,
      product: product,
      product_variant: product_variant
    } do
      line_item =
        LineItem
        |> Ash.Changeset.for_create(:create, %{
          order_id: order.id,
          product_id: product.id,
          product_name: product.name,
          product_image_slug: product.image_slug,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage
        })
        |> Ash.create!(authorize?: false)

      assert line_item.quantity == 1
    end

    test "quantity can only be 1 or greater", %{
      order: order,
      tax_rate: tax_rate,
      product: product,
      product_variant: product_variant
    } do
      assert {:error, _} =
               LineItem
               |> Ash.Changeset.for_create(:create, %{
                 order_id: order.id,
                 product_id: product.id,
                 product_name: product.name,
                 product_image_slug: product.image_slug,
                 product_variant_id: product_variant.id,
                 quantity: 0,
                 unit_price: product_variant.price,
                 tax_rate: tax_rate.percentage
               })
               |> Ash.create()
    end

    test "increments quantity", %{order: order, tax_rate: tax_rate, product: product, product_variant: product_variant} do
      line_item =
        LineItem
        |> Ash.Changeset.for_create(:create, %{
          order_id: order.id,
          product_id: product.id,
          product_name: product.name,
          product_image_slug: product.image_slug,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage
        })
        |> Ash.create!(authorize?: false)
        |> Ash.Changeset.for_update(:increment_quantity)
        |> Ash.update!(authorize?: false)

      assert line_item.quantity == 2
    end

    test "decrements quantity", %{order: order, tax_rate: tax_rate, product: product, product_variant: product_variant} do
      line_item =
        LineItem
        |> Ash.Changeset.for_create(:create, %{
          order_id: order.id,
          product_id: product.id,
          product_name: product.name,
          product_image_slug: product.image_slug,
          product_variant_id: product_variant.id,
          quantity: 3,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage
        })
        |> Ash.create!(authorize?: false)
        |> Ash.Changeset.for_update(:decrement_quantity)
        |> Ash.update!(authorize?: false)

      assert line_item.quantity == 2
    end

    test "decrements quantity no lower than 1", %{
      order: order,
      tax_rate: tax_rate,
      product: product,
      product_variant: product_variant
    } do
      line_item =
        LineItem
        |> Ash.Changeset.for_create(:create, %{
          order_id: order.id,
          product_id: product.id,
          product_name: product.name,
          product_image_slug: product.image_slug,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage
        })
        |> Ash.create!(authorize?: false)
        |> Ash.Changeset.for_update(:decrement_quantity)
        |> Ash.update!(authorize?: false)

      assert line_item.quantity == 1
    end

    test "promotion_applied? returns true if promotion applied to order", %{
      tax_rate: tax_rate,
      product: product,
      product_variant: product_variant
    } do
      promotion = generate(promotion(discount_percentage: "0.20"))
      order = generate(order())
      order = Order.add_promotion_with_id!(order, promotion.id, authorize?: false)

      line_item =
        LineItem
        |> Ash.Changeset.for_create(:create, %{
          order_id: order.id,
          product_id: product.id,
          product_name: product.name,
          product_image_slug: product.image_slug,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage
        })
        |> Ash.create!(authorize?: false)
        |> Ash.load!(:promotion_applied?)

      assert line_item.promotion_applied? == true
    end

    test "promotion_applied? returns false if no promotion applied to order", %{
      order: order,
      tax_rate: tax_rate,
      product: product,
      product_variant: product_variant
    } do
      line_item =
        LineItem
        |> Ash.Changeset.for_create(:create, %{
          order_id: order.id,
          product_id: product.id,
          product_name: product.name,
          product_image_slug: product.image_slug,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage
        })
        |> Ash.create!(authorize?: false)
        |> Ash.load!(:promotion_applied?)

      assert line_item.promotion_applied? == false
    end
  end
end
