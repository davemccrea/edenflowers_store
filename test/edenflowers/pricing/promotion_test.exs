defmodule Edenflowers.Pricing.PromotionTest do
  use Edenflowers.DataCase, async: true

  alias Edenflowers.Orders
  alias Edenflowers.Pricing
  alias Edenflowers.Pricing.Promotion

  describe "Promotion Resource" do
    test "gets promotion using a mixed-case code with surrounding whitespace" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_rate: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19]
      })
      |> Ash.create!(authorize?: false)

      assert {:ok, %Promotion{}} =
               Pricing.get_promotion_by_code(" Christmas20 ", ~D[2024-12-20])
    end

    test "fails to get promotion if code doesn't match" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_rate: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19]
      })
      |> Ash.create!(authorize?: false)

      assert {:error, %Ash.Error.Invalid{}} = Pricing.get_promotion_by_code("AUTUMN20", ~D[2024-12-20])
    end

    test "fails to get promotion if current date is before start date" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_rate: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19]
      })
      |> Ash.create!(authorize?: false)

      assert {:error, %Ash.Error.Invalid{}} = Pricing.get_promotion_by_code("CHRISTMAS20", ~D[2024-12-18])
    end

    test "gets promotion if current date is same as start date" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_rate: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19]
      })
      |> Ash.create!(authorize?: false)

      assert {:ok, %Promotion{}} =
               Pricing.get_promotion_by_code("CHRISTMAS20", ~D[2024-12-19])
    end

    test "gets promotion if current date is after start date and on expiration date" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_rate: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19],
        expiration_date: ~D[2024-12-22]
      })
      |> Ash.create!(authorize?: false)

      assert {:ok, %Promotion{}} =
               Pricing.get_promotion_by_code("CHRISTMAS20", ~D[2024-12-22])
    end

    test "fails to get promotion if current date is after expiration date" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_rate: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19],
        expiration_date: ~D[2024-12-22]
      })
      |> Ash.create!(authorize?: false)

      assert {:error, %Ash.Error.Invalid{}} = Pricing.get_promotion_by_code("CHRISTMAS20", ~D[2024-12-23])
    end
  end

  describe "Promotion usage tracking" do
    import Generator

    test "counts placed orders only" do
      promotion = generate(promotion())
      use_promotion(promotion, 2)
      generate(order(state: :payment, promotion_id: promotion.id))

      assert Ash.load!(promotion, :usage).usage == 2
    end

    test "counts an order once it is finalized with the promotion" do
      tax_rate = generate(tax_rate())
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id))
      promotion = generate(promotion(minimum_cart_total: "0"))

      order =
        generate(
          order(
            state: :payment,
            promotion_id: promotion.id,
            discount_rate: promotion.discount_rate,
            payment_intent_id: "pi_test"
          )
        )

      generate(line_item(order_id: order.id, product_variant_id: product_variant.id))

      order = Ash.load!(order, :grand_total, authorize?: false)
      assert Ash.load!(promotion, :usage).usage == 0

      {:ok, _order} =
        Orders.finalize_checkout(order.id, order.payment_intent_id, %{amount_paid: order.grand_total},
          authorize?: false
        )

      assert Ash.load!(promotion, :usage).usage == 1
    end
  end

  describe "Promotion usage limits" do
    import Generator

    defp limited_promotion(code, usage_limit) do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "Limited #{code}",
        code: code,
        discount_rate: "0.10",
        minimum_cart_total: "0",
        usage_limit: usage_limit
      })
      |> Ash.create!(authorize?: false)
    end

    test "rejects promotion code when usage equals usage_limit" do
      promotion = limited_promotion("LIMITED", 5)
      use_promotion(promotion, 5)

      assert {:error, %Ash.Error.Invalid{}} = Pricing.get_promotion_by_code("LIMITED", Edenflowers.ShopTime.today())
    end

    test "allows promotion code when usage is below usage_limit" do
      promotion = limited_promotion("LIMITED10", 5)
      use_promotion(promotion, 4)

      assert {:ok, %Promotion{id: id}} = Pricing.get_promotion_by_code("LIMITED10", Edenflowers.ShopTime.today())
      assert id == promotion.id
    end

    test "counts usage for a guest, who can't read other people's orders" do
      promotion = limited_promotion("GUESTLIMIT", 1)
      use_promotion(promotion)

      assert {:error, %Ash.Error.Invalid{}} =
               Pricing.get_promotion_by_code("GUESTLIMIT", Edenflowers.ShopTime.today(), actor: nil)
    end

    test "allows unlimited usage when usage_limit is nil" do
      promotion = limited_promotion("UNLIMITED", nil)
      use_promotion(promotion, 20)

      assert {:ok, %Promotion{id: id}} = Pricing.get_promotion_by_code("UNLIMITED", Edenflowers.ShopTime.today())
      assert id == promotion.id
    end

    test "prevents applying promotion to order when usage limit reached" do
      tax_rate = generate(tax_rate())
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id, price: "30.00"))

      promotion = limited_promotion("MAXED", 10)
      use_promotion(promotion, 10)

      order = Orders.create_for_checkout!(authorize?: false)
      generate(line_item(order_id: order.id, product_variant_id: product_variant.id))

      assert {:error, %Ash.Error.Invalid{}} = Orders.add_promotion_with_code(order, "MAXED", authorize?: false)
    end
  end
end
