defmodule Edenflowers.Store.PromotionTest do
  alias Edenflowers.Store.Promotion
  use Edenflowers.DataCase

  describe "Promotion Resource" do
    test "creates a promotion" do
      assert {:ok, _promotion} =
               Promotion
               |> Ash.Changeset.for_create(:create, %{
                 name: "A promotion",
                 code: "CHRISTMAS20",
                 discount_percentage: "0.20",
                 minimum_cart_total: "30.00",
                 start_date: ~D[2024-12-19],
                 expiration_date: ~D[2024-12-31]
               })
               |> Ash.create(authorize?: false)
    end

    test "gets promotion using a code with mixed case" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_percentage: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19]
      })
      |> Ash.create!(authorize?: false)

      assert {:ok, %Promotion{}} =
               Promotion
               |> Ash.Query.for_read(:get_by_code, %{code: "Christmas20", today: ~D[2024-12-20]})
               |> Ash.read_one()
    end

    test "gets promotion using a code with leading and trailing whitespace" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_percentage: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19]
      })
      |> Ash.create!(authorize?: false)

      assert {:ok, %Promotion{}} =
               Promotion
               |> Ash.Query.for_read(:get_by_code, %{code: " CHRISTMAS20 ", today: ~D[2024-12-20]})
               |> Ash.read_one()
    end

    test "fails to get promotion if code doesn't match" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_percentage: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19]
      })
      |> Ash.create!(authorize?: false)

      assert {:ok, nil} =
               Promotion
               |> Ash.Query.for_read(:get_by_code, %{code: "AUTUMN20", today: ~D[2024-12-20]})
               |> Ash.read_one()
    end

    test "fails to get promotion if current date is before start date" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_percentage: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19]
      })
      |> Ash.create!(authorize?: false)

      assert {:ok, nil} =
               Promotion
               |> Ash.Query.for_read(:get_by_code, %{code: "CHRISTMAS20", today: ~D[2024-12-18]})
               |> Ash.read_one()
    end

    test "gets promotion if current date is same as start date" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_percentage: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19]
      })
      |> Ash.create!(authorize?: false)

      assert {:ok, %Promotion{}} =
               Promotion
               |> Ash.Query.for_read(:get_by_code, %{code: "CHRISTMAS20", today: ~D[2024-12-19]})
               |> Ash.read_one()
    end

    test "gets promotion if current date is after start date and before expiration date" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_percentage: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19],
        expiration_date: ~D[2024-12-22]
      })
      |> Ash.create!(authorize?: false)

      assert {:ok, %Promotion{}} =
               Promotion
               |> Ash.Query.for_read(:get_by_code, %{code: "CHRISTMAS20", today: ~D[2024-12-21]})
               |> Ash.read_one()
    end

    test "gets promotion if current date is after start date and on expiration date" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_percentage: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19],
        expiration_date: ~D[2024-12-22]
      })
      |> Ash.create!(authorize?: false)

      assert {:ok, %Promotion{}} =
               Promotion
               |> Ash.Query.for_read(:get_by_code, %{code: "CHRISTMAS20", today: ~D[2024-12-22]})
               |> Ash.read_one()
    end

    test "fails to get promotion if current date is after expiration date" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_percentage: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19],
        expiration_date: ~D[2024-12-22]
      })
      |> Ash.create!(authorize?: false)

      assert {:ok, nil} =
               Promotion
               |> Ash.Query.for_read(:get_by_code, %{code: "CHRISTMAS20", today: ~D[2024-12-23]})
               |> Ash.read_one()
    end

    test "gets promotion using code_interface" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_percentage: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19]
      })
      |> Ash.create!(authorize?: false)

      assert {:ok, %Promotion{}} = Promotion.get_by_code("CHRISTMAS20")
    end
  end

  describe "Promotion usage tracking" do
    import Generator

    test "starts with usage of 0" do
      promotion = generate(promotion())
      assert promotion.usage == 0
    end

    test "increments usage count" do
      promotion = generate(promotion())
      assert promotion.usage == 0

      # Increment usage once
      {:ok, updated} = Promotion.increment_usage(promotion, authorize?: false)
      assert updated.usage == 1

      # Increment again
      {:ok, updated2} = Promotion.increment_usage(updated, authorize?: false)
      assert updated2.usage == 2
    end

    test "increments usage when order is finalized with promotion" do
      alias Edenflowers.Store.Order

      tax_rate = generate(tax_rate())
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id))
      promotion = generate(promotion(minimum_cart_total: "0"))

      assert promotion.usage == 0

      # Create order with promotion
      order = generate(order(promotion_id: promotion.id, payment_intent_id: "pi_test"))

      # Add line item
      _line_item =
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

      # Finalize checkout
      {:ok, _order} = Order.finalise_checkout(order.id, authorize?: false)

      # Check usage was incremented
      {:ok, updated_promotion} = Promotion.get_by_id(promotion.id, authorize?: false)
      assert updated_promotion.usage == 1
    end
  end

  describe "Promotion usage limits" do
    import Generator

    test "rejects promotion code when usage equals usage_limit" do
      # Create promotion with usage_limit
      {:ok, promotion} =
        Promotion
        |> Ash.Changeset.for_create(:create, %{
          name: "Limited Promo",
          code: "LIMITED",
          discount_percentage: "0.10",
          minimum_cart_total: "0",
          usage_limit: 5
        })
        |> Ash.create(authorize?: false)

      # Increment usage to match limit using the increment_usage action
      {:ok, _} = Promotion.increment_usage(promotion, authorize?: false)
      {:ok, _} = Promotion.increment_usage(promotion, authorize?: false)
      {:ok, _} = Promotion.increment_usage(promotion, authorize?: false)
      {:ok, _} = Promotion.increment_usage(promotion, authorize?: false)
      {:ok, _} = Promotion.increment_usage(promotion, authorize?: false)

      # Should not be found because usage >= usage_limit
      assert {:ok, nil} =
               Promotion
               |> Ash.Query.for_read(:get_by_code, %{code: "LIMITED", today: Date.utc_today()})
               |> Ash.read_one()
    end

    test "allows promotion code when usage is below usage_limit" do
      # Create promotion with usage_limit
      {:ok, promotion} =
        Promotion
        |> Ash.Changeset.for_create(:create, %{
          name: "Limited Promo 10",
          code: "LIMITED10",
          discount_percentage: "0.10",
          minimum_cart_total: "0",
          usage_limit: 5
        })
        |> Ash.create(authorize?: false)

      # Increment usage to 4 (below limit of 5)
      {:ok, _} = Promotion.increment_usage(promotion, authorize?: false)
      {:ok, _} = Promotion.increment_usage(promotion, authorize?: false)
      {:ok, _} = Promotion.increment_usage(promotion, authorize?: false)
      {:ok, promotion} = Promotion.increment_usage(promotion, authorize?: false)

      # Should be found because usage < usage_limit
      assert {:ok, %Promotion{id: id}} =
               Promotion
               |> Ash.Query.for_read(:get_by_code, %{code: "LIMITED10", today: Date.utc_today()})
               |> Ash.read_one()

      assert id == promotion.id
    end

    test "allows unlimited usage when usage_limit is nil" do
      # Create promotion without usage_limit (defaults to nil)
      {:ok, promotion} =
        Promotion
        |> Ash.Changeset.for_create(:create, %{
          name: "Unlimited Promo",
          code: "UNLIMITED",
          discount_percentage: "0.10",
          minimum_cart_total: "0"
        })
        |> Ash.create(authorize?: false)

      # Increment usage many times to simulate high usage
      promotion =
        Enum.reduce(1..100, promotion, fn _, promo ->
          {:ok, updated} = Promotion.increment_usage(promo, authorize?: false)
          updated
        end)

      assert promotion.usage == 100

      # Should be found even with high usage because there's no limit
      assert {:ok, %Promotion{id: id}} =
               Promotion
               |> Ash.Query.for_read(:get_by_code, %{code: "UNLIMITED", today: Date.utc_today()})
               |> Ash.read_one()

      assert id == promotion.id
    end

    test "prevents applying promotion to order when usage limit reached" do
      alias Edenflowers.Store.Order

      tax_rate = generate(tax_rate())
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id, price: "30.00"))

      # Create promotion with usage_limit
      {:ok, promotion} =
        Promotion
        |> Ash.Changeset.for_create(:create, %{
          name: "Maxed Out Promo",
          code: "MAXED",
          discount_percentage: "0.20",
          minimum_cart_total: "0",
          usage_limit: 10
        })
        |> Ash.create(authorize?: false)

      # Increment usage to limit (10 times)
      Enum.each(1..10, fn _ ->
        {:ok, _} = Promotion.increment_usage(promotion, authorize?: false)
      end)

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

      # Try to apply promotion using code - should fail
      assert {:error, error} = Order.add_promotion_with_code(order, "MAXED", authorize?: false)
      assert %Ash.Error.Invalid{} = error
    end
  end

  describe "Promotion discount_percentage validations" do
    test "rejects discount_percentage of 0" do
      assert {:error, error} =
               Promotion
               |> Ash.Changeset.for_create(:create, %{
                 name: "Invalid Promo",
                 code: "ZERO",
                 discount_percentage: "0",
                 minimum_cart_total: "0"
               })
               |> Ash.create(authorize?: false)

      assert %Ash.Error.Invalid{} = error
    end

    test "rejects negative discount_percentage" do
      assert {:error, error} =
               Promotion
               |> Ash.Changeset.for_create(:create, %{
                 name: "Invalid Promo",
                 code: "NEGATIVE",
                 discount_percentage: "-0.10",
                 minimum_cart_total: "0"
               })
               |> Ash.create(authorize?: false)

      assert %Ash.Error.Invalid{} = error
    end

    test "rejects discount_percentage above 1.0" do
      assert {:error, error} =
               Promotion
               |> Ash.Changeset.for_create(:create, %{
                 name: "Invalid Promo",
                 code: "TOOBIG",
                 discount_percentage: "1.01",
                 minimum_cart_total: "0"
               })
               |> Ash.create(authorize?: false)

      assert %Ash.Error.Invalid{} = error
    end

    test "accepts discount_percentage of 1.0 (100% off)" do
      assert {:ok, promotion} =
               Promotion
               |> Ash.Changeset.for_create(:create, %{
                 name: "Free Promo",
                 code: "FREE100",
                 discount_percentage: "1.0",
                 minimum_cart_total: "0"
               })
               |> Ash.create(authorize?: false)

      assert Decimal.equal?(promotion.discount_percentage, "1.0")
    end

    test "accepts small discount_percentage like 0.01 (1% off)" do
      assert {:ok, promotion} =
               Promotion
               |> Ash.Changeset.for_create(:create, %{
                 name: "Small Promo",
                 code: "TINY",
                 discount_percentage: "0.01",
                 minimum_cart_total: "0"
               })
               |> Ash.create(authorize?: false)

      assert Decimal.equal?(promotion.discount_percentage, "0.01")
    end
  end

  describe "Promotion unique code constraint" do
    import Generator

    test "prevents duplicate promotion codes" do
      generate(promotion(code: "DUPLICATE"))

      assert {:error, error} =
               Promotion
               |> Ash.Changeset.for_create(:create, %{
                 name: "Second Promo",
                 code: "DUPLICATE",
                 discount_percentage: "0.15",
                 minimum_cart_total: "0"
               })
               |> Ash.create(authorize?: false)

      assert %Ash.Error.Invalid{} = error
    end

    test "enforces case-insensitive uniqueness for codes" do
      generate(promotion(code: "CaseTest"))

      assert {:error, error} =
               Promotion
               |> Ash.Changeset.for_create(:create, %{
                 name: "Second Promo",
                 code: "CASETEST",
                 discount_percentage: "0.15",
                 minimum_cart_total: "0"
               })
               |> Ash.create(authorize?: false)

      assert %Ash.Error.Invalid{} = error
    end
  end
end
