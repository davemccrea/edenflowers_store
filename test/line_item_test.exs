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
               |> Ash.Changeset.for_create(:add_to_cart, %{
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
        |> Ash.Changeset.for_create(:add_to_cart, %{
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
               |> Ash.Changeset.for_create(:add_to_cart, %{
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
        |> Ash.Changeset.for_create(:add_to_cart, %{
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
        |> Ash.Changeset.for_create(:add_to_cart, %{
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
        |> Ash.Changeset.for_create(:add_to_cart, %{
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
      promotion = generate(promotion(discount_percentage: "0.20", minimum_cart_total: "0"))
      order = generate(order())

      # Add line item first
      line_item =
        LineItem
        |> Ash.Changeset.for_create(:add_to_cart, %{
          order_id: order.id,
          product_id: product.id,
          product_name: product.name,
          product_image_slug: product.image_slug,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage
        })
        |> Ash.create!(authorize?: false)

      # Then apply promotion
      _order = Order.add_promotion_with_id!(order, promotion.id, authorize?: false)

      line_item = Ash.load!(line_item, :promotion_applied?)

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
        |> Ash.Changeset.for_create(:add_to_cart, %{
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

  describe "Card line items" do
    setup do
      order = generate(order())

      gift_order =
        order
        |> Ash.Changeset.for_update(:update_gift, %{gift: true})
        |> Ash.update!(authorize?: false)

      cards_category = generate(product_category(slug: "cards", draft: false))
      card_tax_rate = generate(tax_rate())

      card_product =
        generate(product(product_category_id: cards_category.id, tax_rate_id: card_tax_rate.id, draft: false))

      card_variant = generate(product_variant(product_id: card_product.id, draft: false))

      %{gift_order: gift_order, card_product: card_product, card_variant: card_variant}
    end

    test "add_card creates a line item with is_card set to true",
         %{gift_order: gift_order, card_product: card_product, card_variant: card_variant} do
      assert {:ok, line_item} =
               LineItem.add_card(%{
                 order_id: gift_order.id,
                 product_id: card_product.id,
                 product_variant_id: card_variant.id,
                 product_name: card_product.name,
                 product_image_slug: card_variant.image_slug,
                 quantity: 1,
                 unit_price: card_variant.price,
                 tax_rate: Decimal.new("0.24")
               })

      assert line_item.is_card == true
    end

    test "add_card is rejected for non-gift orders",
         %{card_product: card_product, card_variant: card_variant} do
      non_gift_order = generate(order())

      assert {:error, _} =
               LineItem.add_card(%{
                 order_id: non_gift_order.id,
                 product_id: card_product.id,
                 product_variant_id: card_variant.id,
                 product_name: card_product.name,
                 product_image_slug: card_variant.image_slug,
                 quantity: 1,
                 unit_price: card_variant.price,
                 tax_rate: Decimal.new("0.24")
               })
    end

    test "add_card is rejected when order is not in checkout state",
         %{card_product: card_product, card_variant: card_variant} do
      completed_order =
        generate(order(state: :order))
        |> Ash.Changeset.for_update(:update_gift, %{gift: true})
        |> Ash.update!(authorize?: false)

      assert {:error, _} =
               LineItem.add_card(%{
                 order_id: completed_order.id,
                 product_id: card_product.id,
                 product_variant_id: card_variant.id,
                 product_name: card_product.name,
                 product_image_slug: card_variant.image_slug,
                 quantity: 1,
                 unit_price: card_variant.price,
                 tax_rate: Decimal.new("0.24")
               })
    end

    test "update_card_message persists the card message",
         %{gift_order: gift_order, card_product: card_product, card_variant: card_variant} do
      {:ok, card_item} =
        LineItem.add_card(
          %{
            order_id: gift_order.id,
            product_id: card_product.id,
            product_variant_id: card_variant.id,
            product_name: card_product.name,
            product_image_slug: card_variant.image_slug,
            quantity: 1,
            unit_price: card_variant.price,
            tax_rate: Decimal.new("0.24")
          },
          authorize?: false
        )

      assert {:ok, updated} = LineItem.update_card_message(card_item, "Happy birthday!", authorize?: false)
      assert updated.card_message == "Happy birthday!"
    end
  end
end
