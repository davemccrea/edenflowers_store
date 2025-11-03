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
end
