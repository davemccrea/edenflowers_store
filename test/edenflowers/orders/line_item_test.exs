defmodule Edenflowers.Orders.LineItemTest do
  use Edenflowers.DataCase
  import Generator
  alias Edenflowers.Orders.{Order, LineItem}

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
      promotion = generate(promotion(discount_rate: "0.20", minimum_cart_total: "0"))
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

  describe "duplicate-variant upsert" do
    test "adding the same variant twice produces one row with quantity 2", %{
      order: order,
      product_variant: product_variant
    } do
      first =
        LineItem
        |> Ash.Changeset.for_create(:add_to_cart, %{
          order_id: order.id,
          product_variant_id: product_variant.id
        })
        |> Ash.create!(authorize?: false)

      second =
        LineItem
        |> Ash.Changeset.for_create(:add_to_cart, %{
          order_id: order.id,
          product_variant_id: product_variant.id
        })
        |> Ash.create!(authorize?: false)

      assert first.id == second.id
      assert second.quantity == 2

      line_items = Ash.read!(LineItem, authorize?: false)
      assert length(line_items) == 1
    end

    test "adding with explicit quantities sums the existing and incoming values", %{
      order: order,
      product_variant: product_variant
    } do
      LineItem
      |> Ash.Changeset.for_create(:add_to_cart, %{
        order_id: order.id,
        product_variant_id: product_variant.id,
        quantity: 3
      })
      |> Ash.create!(authorize?: false)

      line_item =
        LineItem
        |> Ash.Changeset.for_create(:add_to_cart, %{
          order_id: order.id,
          product_variant_id: product_variant.id,
          quantity: 1
        })
        |> Ash.create!(authorize?: false)

      assert line_item.quantity == 4
    end

    test "adding different variants produces separate rows", %{
      order: order,
      product: product,
      product_variant: first_variant
    } do
      second_variant = generate(product_variant(product_id: product.id))

      LineItem
      |> Ash.Changeset.for_create(:add_to_cart, %{
        order_id: order.id,
        product_variant_id: first_variant.id
      })
      |> Ash.create!(authorize?: false)

      LineItem
      |> Ash.Changeset.for_create(:add_to_cart, %{
        order_id: order.id,
        product_variant_id: second_variant.id
      })
      |> Ash.create!(authorize?: false)

      line_items = Ash.read!(LineItem, authorize?: false)
      assert length(line_items) == 2
      assert Enum.all?(line_items, &(&1.quantity == 1))
    end

    test "duplicate add preserves the original price snapshot", %{
      order: order,
      product_variant: product_variant
    } do
      original_price = product_variant.price

      first =
        LineItem
        |> Ash.Changeset.for_create(:add_to_cart, %{
          order_id: order.id,
          product_variant_id: product_variant.id
        })
        |> Ash.create!(authorize?: false)

      assert Decimal.equal?(first.unit_price, original_price)

      product_variant
      |> Ash.Changeset.for_update(:update, %{price: Decimal.add(original_price, 99)})
      |> Ash.update!(authorize?: false)

      second =
        LineItem
        |> Ash.Changeset.for_create(:add_to_cart, %{
          order_id: order.id,
          product_variant_id: product_variant.id
        })
        |> Ash.create!(authorize?: false)

      assert Decimal.equal?(second.unit_price, original_price)
      assert second.quantity == 2
    end
  end
end
