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
    test "creates an order item", %{order: order, product_variant: product_variant} do
      assert {:ok, _} =
               LineItem
               |> Ash.Changeset.for_create(:add_to_cart, %{
                 order_id: order.id,
                 product_variant_id: product_variant.id
               })
               |> Ash.create(authorize?: false)
    end

    test "derives unit_price, tax_rate, product snapshot from variant on add_to_cart", %{
      order: order,
      tax_rate: tax_rate,
      product: product,
      product_variant: product_variant
    } do
      assert {:ok, line_item} =
               LineItem
               |> Ash.Changeset.for_create(:add_to_cart, %{
                 order_id: order.id,
                 product_variant_id: product_variant.id
               })
               |> Ash.create(authorize?: false)

      assert Decimal.equal?(line_item.unit_price, product_variant.price)
      assert Decimal.equal?(line_item.tax_rate, tax_rate.percentage)
      assert line_item.product_id == product.id
      assert line_item.product_name == product.name
      assert line_item.product_image_slug == product_variant.image_slug
    end

    test "ignores client-supplied unit_price, tax_rate, product fields (security)", %{
      order: order,
      tax_rate: tax_rate,
      product: product,
      product_variant: product_variant
    } do
      # The narrowed accept list means these inputs are not user-settable.
      # Whether Ash rejects them at input validation or simply ignores them,
      # the resulting line item must reflect the canonical variant values.
      result =
        LineItem
        |> Ash.Changeset.for_create(:add_to_cart, %{
          order_id: order.id,
          product_variant_id: product_variant.id,
          unit_price: Decimal.new("0.01"),
          tax_rate: Decimal.new("0"),
          product_name: "spoof",
          product_image_slug: "spoof.png",
          product_id: Ecto.UUID.generate()
        })
        |> Ash.create(authorize?: false)

      case result do
        {:ok, line_item} ->
          # Spoof fields silently ignored — derived values must come from the variant.
          assert Decimal.equal?(line_item.unit_price, product_variant.price)
          assert Decimal.equal?(line_item.tax_rate, tax_rate.percentage)
          assert line_item.product_id == product.id
          assert line_item.product_name == product.name
          assert line_item.product_image_slug == product_variant.image_slug

        {:error, %Ash.Error.Invalid{}} ->
          # Spoof fields rejected at input validation — also acceptable.
          :ok
      end
    end

    test "rejects add_to_cart with unknown product_variant_id", %{order: order} do
      assert {:error, _} =
               LineItem
               |> Ash.Changeset.for_create(:add_to_cart, %{
                 order_id: order.id,
                 product_variant_id: Ecto.UUID.generate()
               })
               |> Ash.create(authorize?: false)
    end

    test "default quantity is 1", %{order: order, product_variant: product_variant} do
      line_item =
        LineItem
        |> Ash.Changeset.for_create(:add_to_cart, %{
          order_id: order.id,
          product_variant_id: product_variant.id
        })
        |> Ash.create!(authorize?: false)

      assert line_item.quantity == 1
    end

    test "quantity can only be 1 or greater", %{order: order, product_variant: product_variant} do
      assert {:error, _} =
               LineItem
               |> Ash.Changeset.for_create(:add_to_cart, %{
                 order_id: order.id,
                 product_variant_id: product_variant.id,
                 quantity: 0
               })
               |> Ash.create()
    end

    test "increments quantity", %{order: order, product_variant: product_variant} do
      line_item =
        LineItem
        |> Ash.Changeset.for_create(:add_to_cart, %{
          order_id: order.id,
          product_variant_id: product_variant.id
        })
        |> Ash.create!(authorize?: false)
        |> Ash.Changeset.for_update(:increment_quantity)
        |> Ash.update!(authorize?: false)

      assert line_item.quantity == 2
    end

    test "decrements quantity", %{order: order, product_variant: product_variant} do
      line_item =
        LineItem
        |> Ash.Changeset.for_create(:add_to_cart, %{
          order_id: order.id,
          product_variant_id: product_variant.id,
          quantity: 3
        })
        |> Ash.create!(authorize?: false)
        |> Ash.Changeset.for_update(:decrement_quantity)
        |> Ash.update!(authorize?: false)

      assert line_item.quantity == 2
    end

    test "decrements quantity no lower than 1", %{order: order, product_variant: product_variant} do
      line_item =
        LineItem
        |> Ash.Changeset.for_create(:add_to_cart, %{
          order_id: order.id,
          product_variant_id: product_variant.id
        })
        |> Ash.create!(authorize?: false)
        |> Ash.Changeset.for_update(:decrement_quantity)
        |> Ash.update!(authorize?: false)

      assert line_item.quantity == 1
    end

    test "promotion_applied? returns true if promotion applied to order", %{product_variant: product_variant} do
      promotion = generate(promotion(discount_percentage: "0.20", minimum_cart_total: "0"))
      order = generate(order())

      # Add line item first
      line_item =
        LineItem
        |> Ash.Changeset.for_create(:add_to_cart, %{
          order_id: order.id,
          product_variant_id: product_variant.id
        })
        |> Ash.create!(authorize?: false)

      # Then apply promotion
      _order = Order.add_promotion_with_id!(order, promotion.id, authorize?: false)

      line_item = Ash.load!(line_item, :promotion_applied?)

      assert line_item.promotion_applied? == true
    end

    test "promotion_applied? returns false if no promotion applied to order", %{
      order: order,
      product_variant: product_variant
    } do
      line_item =
        LineItem
        |> Ash.Changeset.for_create(:add_to_cart, %{
          order_id: order.id,
          product_variant_id: product_variant.id
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
        |> Ash.Changeset.for_update(:set_gift, %{gift: true})
        |> Ash.update!(authorize?: false)

      cards_category = generate(product_category(slug: "cards", draft: false))
      card_tax_rate = generate(tax_rate())

      card_product =
        generate(product(product_category_id: cards_category.id, tax_rate_id: card_tax_rate.id, draft: false))

      card_variant = generate(product_variant(product_id: card_product.id, draft: false))

      %{
        gift_order: gift_order,
        card_product: card_product,
        card_variant: card_variant,
        card_tax_rate: card_tax_rate
      }
    end

    test "add_card creates a line item with is_card set to true and copies card_size",
         %{gift_order: gift_order, card_variant: card_variant} do
      assert {:ok, line_item} =
               LineItem.add_card(%{
                 order_id: gift_order.id,
                 product_variant_id: card_variant.id,
                 quantity: 1
               })

      assert line_item.is_card == true
      assert line_item.card_size == card_variant.size
    end

    test "add_card derives unit_price/tax_rate/snapshot from variant",
         %{gift_order: gift_order, card_product: card_product, card_variant: card_variant, card_tax_rate: card_tax_rate} do
      assert {:ok, line_item} =
               LineItem.add_card(%{
                 order_id: gift_order.id,
                 product_variant_id: card_variant.id,
                 quantity: 1
               })

      assert Decimal.equal?(line_item.unit_price, card_variant.price)
      assert Decimal.equal?(line_item.tax_rate, card_tax_rate.percentage)
      assert line_item.product_id == card_product.id
      assert line_item.product_name == card_product.name
      assert line_item.product_image_slug == card_variant.image_slug
    end

    test "add_card is rejected for non-gift orders",
         %{card_variant: card_variant} do
      non_gift_order = generate(order())

      assert {:error, _} =
               LineItem.add_card(%{
                 order_id: non_gift_order.id,
                 product_variant_id: card_variant.id,
                 quantity: 1
               })
    end

    test "add_card is rejected when order is not in checkout state",
         %{card_variant: card_variant} do
      completed_order =
        generate(order(state: :placed))
        |> Ash.Changeset.for_update(:set_gift, %{gift: true})
        |> Ash.update!(authorize?: false)

      assert {:error, _} =
               LineItem.add_card(%{
                 order_id: completed_order.id,
                 product_variant_id: card_variant.id,
                 quantity: 1
               })
    end
  end
end
