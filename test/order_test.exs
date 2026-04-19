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
                 recipient_name: "Jane Doe"
               })
               |> Ash.update(authorize?: false)

      assert order.gift == true
      assert order.recipient_name == "Jane Doe"
    end

    test "clears recipient_name when switching from gift=true to gift=false" do
      order = Order.create_for_checkout!(authorize?: false)

      # First set gift=true with recipient info
      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:save_step_2, %{
          gift: true,
          recipient_name: "John Smith"
        })
        |> Ash.update(authorize?: false)

      assert order.recipient_name == "John Smith"

      # Now change to gift=false - should clear fields
      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:save_step_2, %{
          gift: false
        })
        |> Ash.update(authorize?: false)

      assert order.gift == false
      assert is_nil(order.recipient_name)
    end

    test "retains recipient_name when gift remains true" do
      order = Order.create_for_checkout!(authorize?: false)

      # First set gift=true with recipient info
      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:save_step_2, %{
          gift: true,
          recipient_name: "Alice Johnson"
        })
        |> Ash.update(authorize?: false)

      # Update with gift still true - should retain fields
      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:save_step_2, %{
          gift: true,
          recipient_name: "Alice Johnson"
        })
        |> Ash.update(authorize?: false)

      assert order.gift == true
      assert order.recipient_name == "Alice Johnson"
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

  describe "User upsert during checkout" do
    test "creates new user when saving step 1 with new email" do
      alias Edenflowers.Accounts.User

      order = Order.create_for_checkout!(authorize?: false)

      # Verify user doesn't exist yet
      assert {:error, %Ash.Error.Invalid{}} = User.get_by_email("newcustomer@example.com", authorize?: false)

      # Save step 1 with customer details
      assert {:ok, order} =
               order
               |> Ash.Changeset.for_update(:save_step_1, %{
                 customer_name: "New Customer",
                 customer_email: "newcustomer@example.com"
               })
               |> Ash.update(authorize?: false)

      # Verify user was created
      assert {:ok, user} = User.get_by_email("newcustomer@example.com", authorize?: false)
      assert user.name == "New Customer"
      assert to_string(user.email) == "newcustomer@example.com"

      # Verify order is assigned to user
      assert order.user_id == user.id
    end

    test "updates existing user name when email already exists" do
      alias Edenflowers.Accounts.User

      # Create existing user
      {:ok, existing_user} = User.upsert("existing@example.com", "Old Name", authorize?: false)
      assert existing_user.name == "Old Name"

      order = Order.create_for_checkout!(authorize?: false)

      # Save step 1 with same email but different name
      assert {:ok, order} =
               order
               |> Ash.Changeset.for_update(:save_step_1, %{
                 customer_name: "Updated Name",
                 customer_email: "existing@example.com"
               })
               |> Ash.update(authorize?: false)

      # Verify user name was updated
      {:ok, updated_user} = User.get_by_email("existing@example.com", authorize?: false)
      assert updated_user.name == "Updated Name"
      assert updated_user.id == existing_user.id

      # Verify order is assigned to same user
      assert order.user_id == existing_user.id
    end

    test "associates order with correct user when multiple orders for same customer" do
      alias Edenflowers.Accounts.User

      # Create first order for customer
      order1 = Order.create_for_checkout!(authorize?: false)

      {:ok, order1} =
        order1
        |> Ash.Changeset.for_update(:save_step_1, %{
          customer_name: "Regular Customer",
          customer_email: "regular@example.com"
        })
        |> Ash.update(authorize?: false)

      # Create second order for same customer
      order2 = Order.create_for_checkout!(authorize?: false)

      {:ok, order2} =
        order2
        |> Ash.Changeset.for_update(:save_step_1, %{
          customer_name: "Regular Customer",
          customer_email: "regular@example.com"
        })
        |> Ash.update(authorize?: false)

      # Verify both orders assigned to same user
      assert order1.user_id == order2.user_id

      # Verify only one user was created
      {:ok, user} = User.get_by_email("regular@example.com", authorize?: false)
      assert user.id == order1.user_id
    end

    test "handles case-insensitive email matching" do
      alias Edenflowers.Accounts.User

      # Create user with lowercase email
      {:ok, user1} = User.upsert("customer@example.com", "Customer", authorize?: false)

      order = Order.create_for_checkout!(authorize?: false)

      # Save step 1 with uppercase email
      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:save_step_1, %{
          customer_name: "Customer",
          customer_email: "CUSTOMER@EXAMPLE.COM"
        })
        |> Ash.update(authorize?: false)

      # Should match existing user (ci_string field)
      assert order.user_id == user1.id

      # Verify only one user exists with this email
      all_users = Ash.read!(User, authorize?: false)
      matching_users = Enum.filter(all_users, fn u -> to_string(u.email) == "customer@example.com" end)
      assert length(matching_users) == 1
    end

    test "preserves user_id through subsequent step updates" do
      alias Edenflowers.Accounts.User

      order = Order.create_for_checkout!(authorize?: false)

      # Save step 1
      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:save_step_1, %{
          customer_name: "Test User",
          customer_email: "test@example.com"
        })
        |> Ash.update(authorize?: false)

      original_user_id = order.user_id
      {:ok, user} = User.get_by_email("test@example.com", authorize?: false)
      assert original_user_id == user.id

      # Update step 2 (gift options)
      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:save_step_2, %{gift: false})
        |> Ash.update(authorize?: false)

      # Verify user_id is unchanged
      assert order.user_id == original_user_id
    end

    test "allows nil customer_name but requires customer_email" do
      alias Edenflowers.Accounts.User

      order = Order.create_for_checkout!(authorize?: false)

      # Save step 1 with only email (name is nil)
      assert {:ok, order} =
               order
               |> Ash.Changeset.for_update(:save_step_1, %{
                 customer_email: "nametest@example.com"
               })
               |> Ash.update(authorize?: false)

      # User should be created with nil name
      {:ok, user} = User.get_by_email("nametest@example.com", authorize?: false)
      assert is_nil(user.name)
      assert order.user_id == user.id

      # But customer_email is required - missing it should fail
      order2 = Order.create_for_checkout!(authorize?: false)

      assert {:error, error} =
               order2
               |> Ash.Changeset.for_update(:save_step_1, %{
                 customer_name: "Test User"
               })
               |> Ash.update(authorize?: false)

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

  describe "Order Step 3 - Fulfillment and delivery" do
    setup do
      tax_rate = generate(tax_rate())

      pickup_option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate.id,
            name: "Store Pickup",
            fulfillment_method: :pickup,
            rate_type: :fixed,
            base_price: "5.00",
            same_day: true,
            order_deadline: ~T[15:00:00]
          )
        )

      delivery_fixed =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate.id,
            name: "Delivery - Fixed",
            fulfillment_method: :delivery,
            rate_type: :fixed,
            base_price: "10.00",
            same_day: false,
            order_deadline: ~T[12:00:00]
          )
        )

      delivery_dynamic =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate.id,
            name: "Delivery - Dynamic",
            fulfillment_method: :delivery,
            rate_type: :dynamic,
            base_price: "5.00",
            price_per_km: "2.00",
            free_dist_km: 3,
            max_dist_km: 15,
            same_day: true,
            order_deadline: ~T[14:00:00]
          )
        )

      %{
        tax_rate: tax_rate,
        pickup_option: pickup_option,
        delivery_fixed: delivery_fixed,
        delivery_dynamic: delivery_dynamic
      }
    end

    test "save_step_3 requires fulfillment_date", %{pickup_option: pickup_option} do
      order = Order.create_for_checkout!(authorize?: false)

      # Set step to 3
      order = Ash.Changeset.for_update(order, :edit_step_3) |> Ash.update!(authorize?: false)

      # Attempt to save without fulfillment_date
      assert {:error, error} =
               order
               |> Ash.Changeset.for_update(:save_step_3, %{
                 fulfillment_option_id: pickup_option.id
               })
               |> Ash.update(authorize?: false)

      assert %Ash.Error.Invalid{} = error
    end

    test "save_step_3 with pickup clears delivery fields", %{pickup_option: pickup_option} do
      order = Order.create_for_checkout!(authorize?: false)
      order = Ash.Changeset.for_update(order, :edit_step_3) |> Ash.update!(authorize?: false)

      # Note: In real flow, delivery_address would trigger HereAPI calls
      # For pickup, we don't need delivery address
      assert {:ok, order} =
               order
               |> Ash.Changeset.for_update(:save_step_3, %{
                 fulfillment_option_id: pickup_option.id,
                 fulfillment_date: Date.add(Date.utc_today(), 1)
               })
               |> Ash.update(authorize?: false)

      assert order.fulfillment_option_id == pickup_option.id
      assert order.fulfillment_amount == Decimal.new("5.00")
      assert order.step == 4

      # Delivery fields should be cleared
      assert is_nil(order.delivery_address)
      assert is_nil(order.calculated_address)
      assert is_nil(order.here_id)
      assert is_nil(order.distance)
      assert is_nil(order.position)
    end

    test "save_step_3 with pickup calculates correct fixed price", %{pickup_option: pickup_option} do
      order = Order.create_for_checkout!(authorize?: false)
      order = Ash.Changeset.for_update(order, :edit_step_3) |> Ash.update!(authorize?: false)

      assert {:ok, order} =
               order
               |> Ash.Changeset.for_update(:save_step_3, %{
                 fulfillment_option_id: pickup_option.id,
                 fulfillment_date: Date.add(Date.utc_today(), 2)
               })
               |> Ash.update(authorize?: false)

      assert Decimal.equal?(order.fulfillment_amount, "5.00")
    end

    test "save_step_3 requires delivery_address for delivery orders", %{delivery_fixed: delivery_fixed} do
      order = Order.create_for_checkout!(authorize?: false)
      order = Ash.Changeset.for_update(order, :edit_step_3) |> Ash.update!(authorize?: false)

      # Attempt delivery without address
      assert {:error, error} =
               order
               |> Ash.Changeset.for_update(:save_step_3, %{
                 fulfillment_option_id: delivery_fixed.id,
                 fulfillment_date: Date.add(Date.utc_today(), 1)
               })
               |> Ash.update(authorize?: false)

      assert %Ash.Error.Invalid{} = error
    end

    test "save_step_3 rejects empty delivery_address for delivery orders", %{delivery_fixed: delivery_fixed} do
      order = Order.create_for_checkout!(authorize?: false)
      order = Ash.Changeset.for_update(order, :edit_step_3) |> Ash.update!(authorize?: false)

      # Attempt delivery with empty string address
      assert {:error, error} =
               order
               |> Ash.Changeset.for_update(:save_step_3, %{
                 fulfillment_option_id: delivery_fixed.id,
                 delivery_address: "",
                 fulfillment_date: Date.add(Date.utc_today(), 1)
               })
               |> Ash.update(authorize?: false)

      assert %Ash.Error.Invalid{} = error
    end

    test "save_step_3 validates fulfillment_date is not in the past", %{pickup_option: pickup_option} do
      order = Order.create_for_checkout!(authorize?: false)
      order = Ash.Changeset.for_update(order, :edit_step_3) |> Ash.update!(authorize?: false)

      yesterday = Date.add(Date.utc_today(), -1)

      # Attempt to save with past date
      assert {:error, error} =
               order
               |> Ash.Changeset.for_update(:save_step_3, %{
                 fulfillment_option_id: pickup_option.id,
                 fulfillment_date: yesterday
               })
               |> Ash.update(authorize?: false)

      assert %Ash.Error.Invalid{} = error
    end
  end

  describe "Order state transitions" do
    test "cannot transition from order back to checkout" do
      order = generate(order(state: :order, payment_status: :paid))

      # Try to set state back to checkout - should now fail
      assert {:error, error} =
               order
               |> Ash.Changeset.for_update(:update, %{state: :checkout})
               |> Ash.update(authorize?: false)

      assert %Ash.Error.Invalid{} = error
    end

    test "finalise_checkout requires payment_intent_id" do
      order = generate(order(payment_intent_id: nil))

      assert {:error, error} = Order.finalise_checkout(order.id, authorize?: false)
      assert %Ash.Error.Invalid{} = error
    end

    test "payment_status transitions from pending to paid" do
      order = generate(order(payment_status: :pending, payment_intent_id: "pi_test"))

      assert {:ok, order} = Order.finalise_checkout(order.id, authorize?: false)
      assert order.payment_status == :paid
    end

    test "cannot finalize order already in :order state" do
      order = generate(order(state: :order, payment_status: :paid, payment_intent_id: "pi_test"))

      # Should now fail with clear error message
      assert {:error, error} = Order.finalise_checkout(order.id, authorize?: false)
      assert %Ash.Error.Invalid{} = error
    end
  end

  describe "Order reset action" do
    test "reset clears all checkout fields and returns to step 1" do
      tax_rate = generate(tax_rate())

      fulfillment_option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate.id,
            name: "Pickup",
            fulfillment_method: :pickup,
            rate_type: :fixed,
            base_price: "5.00"
          )
        )

      promotion = generate(promotion(minimum_cart_total: "0"))

      # Create an order with all fields filled
      order =
        generate(
          order(
            step: 4,
            customer_name: "Test Customer",
            customer_email: "test@example.com",
            gift: true,
            recipient_name: "Recipient",
            recipient_phone_number: "+358401234567",
            delivery_address: "Test Address",
            delivery_instructions: "Ring twice",
            fulfillment_date: Date.add(Date.utc_today(), 1),
            fulfillment_amount: "5.00",
            calculated_address: "Calculated Address",
            here_id: "here123",
            distance: 5000,
            position: "60.1699,24.9384",
            payment_intent_id: "pi_test123",
            promotion_id: promotion.id,
            fulfillment_option_id: fulfillment_option.id
          )
        )

      # Reset the order
      assert {:ok, reset_order} = Order.reset(order, authorize?: false)

      # Verify all fields are cleared
      assert reset_order.step == 1
      assert is_nil(reset_order.customer_name)
      assert is_nil(reset_order.customer_email)
      assert reset_order.gift == false
      assert is_nil(reset_order.recipient_name)
      assert is_nil(reset_order.recipient_phone_number)
      assert is_nil(reset_order.delivery_address)
      assert is_nil(reset_order.delivery_instructions)
      assert is_nil(reset_order.fulfillment_date)
      assert is_nil(reset_order.fulfillment_amount)
      assert is_nil(reset_order.calculated_address)
      assert is_nil(reset_order.here_id)
      assert is_nil(reset_order.distance)
      assert is_nil(reset_order.position)
      assert is_nil(reset_order.payment_intent_id)
      assert is_nil(reset_order.promotion_id)
      assert is_nil(reset_order.fulfillment_option_id)
    end

    test "reset preserves order id and state" do
      order = generate(order(step: 3, customer_name: "Test", customer_email: "test@example.com"))
      original_id = order.id
      original_state = order.state

      assert {:ok, reset_order} = Order.reset(order, authorize?: false)

      # ID and state should remain unchanged
      assert reset_order.id == original_id
      assert reset_order.state == original_state
    end
  end

  describe "Order update_locale action" do
    test "updates locale successfully" do
      order = Order.create_for_checkout!(authorize?: false)
      assert order.locale == "sv-FI"

      assert {:ok, updated_order} = Order.update_locale(order, "en-US", authorize?: false)
      assert updated_order.locale == "en-US"
    end

  end
end
