defmodule Edenflowers.Store.OrderTest do
  use Edenflowers.DataCase
  import Generator
  alias Edenflowers.Store.Order

  describe "Store Resource" do
    test "creates an order for checkout" do
      order = Order.create_for_checkout!(authorize?: false)
      assert order.state == :checkout
      assert order.step == 1
    end

    test "counts number of items in cart" do
      tax_rate = generate(tax_rate())
      product_1 = generate(product(tax_rate_id: tax_rate.id))
      product_1_product_variant_1 = generate(product_variant(product_id: product_1.id))
      product_2 = generate(product(tax_rate_id: tax_rate.id))
      product_2_product_variant_1 = generate(product_variant(product_id: product_2.id))
      order = generate(order())

      _line_item_1 =
        generate(
          line_item(
            order_id: order.id,
            product_id: product_1.id,
            product_name: product_1.name,
            product_image_slug: product_1.image_slug,
            product_variant_id: product_1_product_variant_1.id,
            unit_price: product_1_product_variant_1.price,
            tax_rate: tax_rate.percentage,
            quantity: 2
          )
        )

      _line_item_2 =
        generate(
          line_item(
            order_id: order.id,
            product_id: product_2.id,
            product_name: product_2.name,
            product_image_slug: product_2.image_slug,
            product_variant_id: product_2_product_variant_1.id,
            unit_price: product_2_product_variant_1.price,
            tax_rate: tax_rate.percentage,
            quantity: 1
          )
        )

      order = Ash.load!(order, [:total_items_in_cart], authorize?: false)

      assert order.total_items_in_cart == 3
    end

    test "sums line_total and line_tax_amount correctly when no promotion is applied" do
      tax_rate_1 = generate(tax_rate(percentage: "0.255"))
      product_1 = generate(product(tax_rate_id: tax_rate_1.id))
      product_1_product_variant_1 = generate(product_variant(product_id: product_1.id, price: "40.00"))

      tax_rate_2 = generate(tax_rate(percentage: "0.10"))
      product_2 = generate(product(tax_rate_id: tax_rate_2.id))
      product_2_product_variant_1 = generate(product_variant(product_id: product_2.id, price: "6.00"))

      order = Order.create_for_checkout!(authorize?: false)

      generate(
        line_item(
          order_id: order.id,
          product_id: product_1.id,
          product_name: product_1.name,
          product_image_slug: product_1.image_slug,
          product_variant_id: product_1_product_variant_1.id,
          unit_price: product_1_product_variant_1.price,
          tax_rate: tax_rate_1.percentage,
          quantity: 2
        )
      )

      generate(
        line_item(
          order_id: order.id,
          product_id: product_2.id,
          product_name: product_2.name,
          product_image_slug: product_2.image_slug,
          product_variant_id: product_2_product_variant_1.id,
          unit_price: product_2_product_variant_1.price,
          tax_rate: tax_rate_2.percentage,
          quantity: 1
        )
      )

      order = Ash.load!(order, [:line_total, :line_tax_amount], authorize?: false)

      assert Decimal.equal?(order.line_total, "86.00")
      assert Decimal.equal?(order.line_tax_amount, "21.00")
    end

    test "sums line_total and line_tax_amount correctly when promotion is applied" do
      tax_rate = generate(tax_rate(percentage: "0.255"))
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant_1 = generate(product_variant(product_id: product.id, price: "49.99"))
      product_variant_2 = generate(product_variant(product_id: product.id, price: "29.99"))
      promotion = generate(promotion(discount_percentage: "0.20"))

      order =
        Order.create_for_checkout!(authorize?: false)
        |> Order.add_promotion_with_id!(promotion.id, load: [:promotion_applied?], authorize?: false)

      generate(
        line_item(
          order_id: order.id,
          product_id: product.id,
          product_name: product.name,
          product_image_slug: product.image_slug,
          product_variant_id: product_variant_1.id,
          unit_price: product_variant_1.price,
          tax_rate: tax_rate.percentage,
          quantity: 1
        )
      )

      generate(
        line_item(
          order_id: order.id,
          product_id: product.id,
          product_name: product.name,
          product_image_slug: product.image_slug,
          product_variant_id: product_variant_2.id,
          unit_price: product_variant_2.price,
          tax_rate: tax_rate.percentage,
          quantity: 2
        )
      )

      order = Ash.load!(order, [:line_total, :line_tax_amount], authorize?: false)

      assert order.line_total
             |> Decimal.round(2)
             |> Decimal.equal?("87.98")

      assert order.line_tax_amount
             |> Decimal.round(2)
             |> Decimal.equal?("22.43")
    end

    test "promotion_applied? returns true if promotion applied" do
      promotion = generate(promotion(discount_percentage: "0.20"))

      order =
        Order.create_for_checkout!(authorize?: false)
        |> Order.add_promotion_with_id!(promotion.id, load: [:promotion_applied?], authorize?: false)

      assert order.promotion_applied? == true
    end

    test "promotion_applied? returns false if no promotion applied" do
      order = Order.create_for_checkout!(authorize?: false, load: [:promotion_applied?])
      assert order.promotion_applied? == false
    end
  end

  test "calculates total and tax_amount correctly" do
    tax_rate_2 = generate(tax_rate(percentage: "0.255"))
    tax_rate_1 = generate(tax_rate(percentage: "0.15"))
    product = generate(product(tax_rate_id: tax_rate_2.id))
    product_variant = generate(product_variant(product_id: product.id, price: "29.99"))

    fulfillment_option =
      generate(
        fulfillment_option(
          name: "Pickup",
          fulfillment_method: :pickup,
          rate_type: :fixed,
          base_price: "4.99",
          order_deadline: ~T[12:00:00],
          # Note: using a different tax rate for fulfillment!
          tax_rate_id: tax_rate_1.id
        )
      )

    {:ok, fulfillment_amount} = Edenflowers.Fulfillments.calculate_price(fulfillment_option)

    order =
      Ash.Seed.seed!(Order, %{fulfillment_option_id: fulfillment_option.id, fulfillment_amount: fulfillment_amount})

    _line_item =
      generate(
        line_item(
          order_id: order.id,
          product_id: product.id,
          product_name: product.name,
          product_image_slug: product.image_slug,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate_2.percentage,
          quantity: 2
        )
      )

    order = Ash.load!(order, [:total, :tax_amount], authorize?: false)

    assert order.total
           |> Decimal.round(2)
           |> Decimal.equal?("64.97")

    assert order.tax_amount
           |> Decimal.round(2)
           |> Decimal.equal?("16.04")
  end

  test "calling finalise_checkout updates state and payment_state" do
    order = Ash.Seed.seed!(Order, %{payment_intent_id: "pi_3RMvONL97TreKmaJ1hGJP2QL"})

    assert {:ok, order} = Order.finalise_checkout(order.id, authorize?: false)
    assert order.state == :order
    assert order.payment_status == :paid
    assert %DateTime{} = order.ordered_at
  end

  test "calling finalise_checkout increments promotion usage when promotion is applied" do
    alias Edenflowers.Store.Promotion

    # Create a promotion and order with that promotion
    promotion =
      Ash.Seed.seed!(Promotion, %{
        name: "Test Promotion",
        code: "TEST20",
        discount_percentage: Decimal.new("0.20"),
        minimum_cart_total: Decimal.new("0"),
        usage: 0
      })

    order =
      Ash.Seed.seed!(Order, %{
        payment_intent_id: "pi_test123",
        promotion_id: promotion.id
      })

    # Verify initial usage is 0
    assert promotion.usage == 0

    # Finalize the checkout
    assert {:ok, _order} = Order.finalise_checkout(order.id, authorize?: false)

    # Verify promotion usage incremented to 1
    {:ok, updated_promotion} = Promotion.get_by_id(promotion.id, authorize?: false)
    assert updated_promotion.usage == 1
  end

  test "calling finalise_checkout does not increment usage when no promotion is applied" do
    alias Edenflowers.Store.Promotion

    # Create a promotion but don't apply it to the order
    promotion =
      Ash.Seed.seed!(Promotion, %{
        name: "Test Promotion",
        code: "TEST20",
        discount_percentage: Decimal.new("0.20"),
        minimum_cart_total: Decimal.new("0"),
        usage: 0
      })

    order = Ash.Seed.seed!(Order, %{payment_intent_id: "pi_test123"})

    # Finalize the checkout without promotion
    assert {:ok, _order} = Order.finalise_checkout(order.id, authorize?: false)

    # Verify promotion usage remains 0
    {:ok, unchanged_promotion} = Promotion.get_by_id(promotion.id, authorize?: false)
    assert unchanged_promotion.usage == 0
  end
end
