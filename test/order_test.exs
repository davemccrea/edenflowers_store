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
      promotion = generate(promotion(discount_percentage: "0.20", minimum_cart_total: "0"))

      order = Order.create_for_checkout!(authorize?: false)

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

      order = Order.add_promotion_with_id!(order, promotion.id, load: [:promotion_applied?], authorize?: false)

      order = Ash.load!(order, [:line_total, :line_tax_amount], authorize?: false)

      assert order.line_total
             |> Decimal.round(2)
             |> Decimal.equal?("87.98")

      assert order.line_tax_amount
             |> Decimal.round(2)
             |> Decimal.equal?("22.43")
    end

    test "promotion_applied? returns true if promotion applied" do
      tax_rate = generate(tax_rate())
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id))
      promotion = generate(promotion(discount_percentage: "0.20", minimum_cart_total: "0"))

      order = Order.create_for_checkout!(authorize?: false)

      # Add a line item so we can apply the promotion
      generate(
        line_item(
          order_id: order.id,
          product_id: product.id,
          product_name: product.name,
          product_image_slug: product.image_slug,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage
        )
      )

      order = Order.add_promotion_with_id!(order, promotion.id, load: [:promotion_applied?], authorize?: false)

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
      generate(order(fulfillment_option_id: fulfillment_option.id, fulfillment_amount: fulfillment_amount))

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
    order = generate(order(payment_intent_id: "pi_3RMvONL97TreKmaJ1hGJP2QL"))

    assert {:ok, order} = Order.finalise_checkout(order.id, authorize?: false)
    assert order.state == :order
    assert order.payment_status == :paid
    assert %DateTime{} = order.ordered_at
  end

  test "calling finalise_checkout increments promotion usage when promotion is applied" do
    alias Edenflowers.Store.Promotion

    # Create a promotion and order with that promotion
    promotion =
      generate(
        promotion(
          name: "Test Promotion",
          code: "TEST20",
          discount_percentage: "0.20",
          minimum_cart_total: "0"
        )
      )

    order =
      generate(
        order(
          payment_intent_id: "pi_test123",
          promotion_id: promotion.id
        )
      )

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
      generate(
        promotion(
          name: "Test Promotion",
          code: "TEST20",
          discount_percentage: "0.20",
          minimum_cart_total: "0"
        )
      )

    order = generate(order(payment_intent_id: "pi_test123"))

    # Finalize the checkout without promotion
    assert {:ok, _order} = Order.finalise_checkout(order.id, authorize?: false)

    # Verify promotion usage remains 0
    {:ok, unchanged_promotion} = Promotion.get_by_id(promotion.id, authorize?: false)
    assert unchanged_promotion.usage == 0
  end

  describe "Gift flow validation" do
    test "requires recipient_name when gift is true" do
      order = Order.create_for_checkout!(authorize?: false)

      # Attempt to save step 2 with gift=true but no recipient_name
      assert {:error, error} =
               order
               |> Ash.Changeset.for_update(:save_step_2, %{
                 gift: true,
                 recipient_name: nil
               })
               |> Ash.update(authorize?: false)

      assert %Ash.Error.Invalid{} = error
    end

    test "does not require recipient_name when gift is false" do
      order = Order.create_for_checkout!(authorize?: false)

      # Should succeed without recipient_name when gift is false
      assert {:ok, order} =
               order
               |> Ash.Changeset.for_update(:save_step_2, %{
                 gift: false,
                 recipient_name: nil
               })
               |> Ash.update(authorize?: false)

      assert order.gift == false
      assert is_nil(order.recipient_name)
    end

    test "accepts recipient_name when gift is true" do
      order = Order.create_for_checkout!(authorize?: false)

      # Should succeed with recipient_name when gift is true
      assert {:ok, order} =
               order
               |> Ash.Changeset.for_update(:save_step_2, %{
                 gift: true,
                 recipient_name: "Jane Doe",
                 gift_message: "Happy Birthday!"
               })
               |> Ash.update(authorize?: false)

      assert order.gift == true
      assert order.recipient_name == "Jane Doe"
      assert order.gift_message == "Happy Birthday!"
    end

    test "clears recipient_name and gift_message when switching from gift=true to gift=false" do
      order = Order.create_for_checkout!(authorize?: false)

      # First set gift=true with recipient info
      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:save_step_2, %{
          gift: true,
          recipient_name: "John Smith",
          gift_message: "Congratulations!"
        })
        |> Ash.update(authorize?: false)

      assert order.recipient_name == "John Smith"
      assert order.gift_message == "Congratulations!"

      # Now change to gift=false - should clear fields
      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:save_step_2, %{
          gift: false
        })
        |> Ash.update(authorize?: false)

      assert order.gift == false
      assert is_nil(order.recipient_name)
      assert is_nil(order.gift_message)
    end

    test "retains recipient_name and gift_message when gift remains true" do
      order = Order.create_for_checkout!(authorize?: false)

      # First set gift=true with recipient info
      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:save_step_2, %{
          gift: true,
          recipient_name: "Alice Johnson",
          gift_message: "Get well soon"
        })
        |> Ash.update(authorize?: false)

      # Update with gift still true - should retain fields
      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:save_step_2, %{
          gift: true,
          recipient_name: "Alice Johnson",
          gift_message: "Get well soon - updated"
        })
        |> Ash.update(authorize?: false)

      assert order.gift == true
      assert order.recipient_name == "Alice Johnson"
      assert order.gift_message == "Get well soon - updated"
    end
  end

  describe "Promotion code validation" do
    test "applies promotion using valid code" do
      tax_rate = generate(tax_rate())
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id, price: "30.00"))

      promotion =
        generate(promotion(code: "SUMMER20", discount_percentage: "0.20", minimum_cart_total: "0"))

      order = Order.create_for_checkout!(authorize?: false)

      # Add line item
      generate(
        line_item(
          order_id: order.id,
          product_id: product.id,
          product_name: product.name,
          product_image_slug: product.image_slug,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage
        )
      )

      # Apply promotion using code
      assert {:ok, order} = Order.add_promotion_with_code(order, "SUMMER20", authorize?: false)
      assert order.promotion_id == promotion.id
    end

    test "applies promotion using code with different case" do
      tax_rate = generate(tax_rate())
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id))

      promotion =
        generate(promotion(code: "WINTER10", discount_percentage: "0.10", minimum_cart_total: "0"))

      order = Order.create_for_checkout!(authorize?: false)

      generate(
        line_item(
          order_id: order.id,
          product_id: product.id,
          product_name: product.name,
          product_image_slug: product.image_slug,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage
        )
      )

      # Should work with lowercase
      assert {:ok, order} = Order.add_promotion_with_code(order, "winter10", authorize?: false)
      assert order.promotion_id == promotion.id
    end

    test "applies promotion using code with whitespace" do
      tax_rate = generate(tax_rate())
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id))

      promotion =
        generate(promotion(code: "SPRING15", discount_percentage: "0.15", minimum_cart_total: "0"))

      order = Order.create_for_checkout!(authorize?: false)

      generate(
        line_item(
          order_id: order.id,
          product_id: product.id,
          product_name: product.name,
          product_image_slug: product.image_slug,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage
        )
      )

      # Should work with leading/trailing whitespace
      assert {:ok, order} = Order.add_promotion_with_code(order, " SPRING15 ", authorize?: false)
      assert order.promotion_id == promotion.id
    end

    test "rejects invalid promotion code" do
      tax_rate = generate(tax_rate())
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id))

      order = Order.create_for_checkout!(authorize?: false)

      generate(
        line_item(
          order_id: order.id,
          product_id: product.id,
          product_name: product.name,
          product_image_slug: product.image_slug,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage
        )
      )

      # Try to apply non-existent code
      assert {:error, error} = Order.add_promotion_with_code(order, "INVALID", authorize?: false)
      assert %Ash.Error.Invalid{} = error
    end

    test "rejects expired promotion code" do
      tax_rate = generate(tax_rate())
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id))

      # Create promotion that expired yesterday
      _promotion =
        generate(
          promotion(
            code: "EXPIRED",
            discount_percentage: "0.20",
            minimum_cart_total: "0",
            start_date: Date.add(Date.utc_today(), -30),
            expiration_date: Date.add(Date.utc_today(), -1)
          )
        )

      order = Order.create_for_checkout!(authorize?: false)

      generate(
        line_item(
          order_id: order.id,
          product_id: product.id,
          product_name: product.name,
          product_image_slug: product.image_slug,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage
        )
      )

      # Should fail because promotion is expired
      assert {:error, error} = Order.add_promotion_with_code(order, "EXPIRED", authorize?: false)
      assert %Ash.Error.Invalid{} = error
    end

    test "rejects not-yet-started promotion code" do
      tax_rate = generate(tax_rate())
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id))

      # Create promotion that starts tomorrow
      _promotion =
        generate(
          promotion(
            code: "FUTURE",
            discount_percentage: "0.20",
            minimum_cart_total: "0",
            start_date: Date.add(Date.utc_today(), 1)
          )
        )

      order = Order.create_for_checkout!(authorize?: false)

      generate(
        line_item(
          order_id: order.id,
          product_id: product.id,
          product_name: product.name,
          product_image_slug: product.image_slug,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage
        )
      )

      # Should fail because promotion hasn't started yet
      assert {:error, error} = Order.add_promotion_with_code(order, "FUTURE", authorize?: false)
      assert %Ash.Error.Invalid{} = error
    end

    test "rejects promotion code when cart total is below minimum" do
      tax_rate = generate(tax_rate())
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id, price: "10.00"))

      # Create promotion requiring minimum 50.00
      _promotion =
        generate(
          promotion(
            code: "BIG50",
            discount_percentage: "0.20",
            minimum_cart_total: "50.00"
          )
        )

      order = Order.create_for_checkout!(authorize?: false)

      # Add item worth only 10.00
      generate(
        line_item(
          order_id: order.id,
          product_id: product.id,
          product_name: product.name,
          product_image_slug: product.image_slug,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage
        )
      )

      # Should fail due to minimum cart total validation
      assert {:error, error} = Order.add_promotion_with_code(order, "BIG50", authorize?: false)
      assert %Ash.Error.Invalid{} = error
    end
  end

  describe "Promotion minimum cart total validation" do
    test "applies promotion when cart total meets minimum requirement" do
      tax_rate = generate(tax_rate(percentage: "0.255"))
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id, price: "25.00"))

      # Create promotion requiring minimum 40.00 cart total
      promotion = generate(promotion(discount_percentage: "0.20", minimum_cart_total: "40.00"))

      order = Order.create_for_checkout!(authorize?: false)

      # Add items totaling 50.00 (2 x 25.00)
      generate(
        line_item(
          order_id: order.id,
          product_id: product.id,
          product_name: product.name,
          product_image_slug: product.image_slug,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage,
          quantity: 2
        )
      )

      # Apply promotion - should succeed as 50.00 >= 40.00
      assert {:ok, order} = Order.add_promotion_with_id(order, promotion.id, authorize?: false, load: [:line_total])
      assert order.promotion_id == promotion.id
      # After 20% discount: 50.00 - 10.00 = 40.00
      assert Decimal.equal?(order.line_total, "40.00")
    end

    test "rejects promotion when cart total is below minimum requirement" do
      tax_rate = generate(tax_rate(percentage: "0.255"))
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id, price: "15.00"))

      # Create promotion requiring minimum 50.00 cart total
      promotion = generate(promotion(discount_percentage: "0.20", minimum_cart_total: "50.00"))

      order = Order.create_for_checkout!(authorize?: false)

      # Add items totaling 30.00 (2 x 15.00)
      generate(
        line_item(
          order_id: order.id,
          product_id: product.id,
          product_name: product.name,
          product_image_slug: product.image_slug,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage,
          quantity: 2
        )
      )

      # Apply promotion - should fail as 30.00 < 50.00
      assert {:error, error} = Order.add_promotion_with_id(order, promotion.id, authorize?: false)
      assert %Ash.Error.Invalid{} = error
    end

    test "applies promotion when cart total exactly meets minimum requirement" do
      tax_rate = generate(tax_rate(percentage: "0.10"))
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id, price: "50.00"))

      # Create promotion requiring minimum 50.00 cart total
      promotion = generate(promotion(discount_percentage: "0.15", minimum_cart_total: "50.00"))

      order = Order.create_for_checkout!(authorize?: false)

      # Add item totaling exactly 50.00
      generate(
        line_item(
          order_id: order.id,
          product_id: product.id,
          product_name: product.name,
          product_image_slug: product.image_slug,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage,
          quantity: 1
        )
      )

      # Apply promotion - should succeed as 50.00 == 50.00
      assert {:ok, order} = Order.add_promotion_with_id(order, promotion.id, authorize?: false, load: [:line_total])
      assert order.promotion_id == promotion.id
      # After 15% discount: 50.00 - 7.50 = 42.50
      assert Decimal.equal?(order.line_total, "42.50")
    end

    test "rejects promotion when cart is empty" do
      # Create promotion requiring minimum 20.00 cart total
      promotion = generate(promotion(discount_percentage: "0.10", minimum_cart_total: "20.00"))

      order = Order.create_for_checkout!(authorize?: false)

      # No line items added - cart total is 0
      assert {:error, error} = Order.add_promotion_with_id(order, promotion.id, authorize?: false)
      assert %Ash.Error.Invalid{} = error
    end

    test "applies promotion with 0 minimum cart total to any order" do
      tax_rate = generate(tax_rate(percentage: "0.10"))
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id, price: "5.00"))

      # Create promotion with no minimum requirement
      promotion = generate(promotion(discount_percentage: "0.10", minimum_cart_total: "0"))

      order = Order.create_for_checkout!(authorize?: false)

      # Add small item
      generate(
        line_item(
          order_id: order.id,
          product_id: product.id,
          product_name: product.name,
          product_image_slug: product.image_slug,
          product_variant_id: product_variant.id,
          unit_price: product_variant.price,
          tax_rate: tax_rate.percentage,
          quantity: 1
        )
      )

      # Apply promotion - should succeed regardless of cart size
      assert {:ok, order} = Order.add_promotion_with_id(order, promotion.id, authorize?: false)
      assert order.promotion_id == promotion.id
    end
  end
end
