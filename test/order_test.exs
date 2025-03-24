defmodule Edenflowers.Store.OrderTest do
  alias Edenflowers.Store.Order
  use Edenflowers.DataCase

  import Edenflowers.Fixtures

  describe "Store Resource" do
    test "creates an order" do
      assert {:ok, _order} =
               Order
               |> Ash.Changeset.for_create(:create, %{})
               |> Ash.create()
    end

    # test "completes an order" do
    #   order = fixture(:order, customer_name: "Customer")

    #   order
    #   |> Ash.Changeset.for_update(:complete)
    #   |> Ash.update!()

    #   assert false
    # end

    test "counts number of items in cart" do
      tax_rate = fixture(:tax_rate)
      product_1 = fixture(:product, tax_rate_id: tax_rate.id)
      product_1_product_variant_1 = fixture(:product_variant, product_id: product_1.id)
      product_2 = fixture(:product, tax_rate_id: tax_rate.id)
      product_2_product_variant_1 = fixture(:product_variant, product_id: product_2.id)

      order =
        Order
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create!()

      fixture(:order_item, %{
        order_id: order.id,
        product_variant_id: product_1_product_variant_1.id,
        unit_price: product_1_product_variant_1.price,
        tax_rate: tax_rate.percentage,
        quantity: 2
      })

      fixture(:order_item, %{
        order_id: order.id,
        product_variant_id: product_2_product_variant_1.id,
        unit_price: product_2_product_variant_1.price,
        tax_rate: tax_rate.percentage,
        quantity: 1
      })

      order = Ash.load!(order, [:total_items_in_cart])

      assert order.total_items_in_cart == 3
    end

    test "sums line_total and line_tax_amount correctly when no promotion is applied" do
      tax_rate_1 = fixture(:tax_rate, percentage: "0.255")
      product_1 = fixture(:product, tax_rate_id: tax_rate_1.id)
      product_1_product_variant_1 = fixture(:product_variant, product_id: product_1.id, price: "40.00")

      tax_rate_2 = fixture(:tax_rate, percentage: "0.10")
      product_2 = fixture(:product, tax_rate_id: tax_rate_2.id)
      product_2_product_variant_1 = fixture(:product_variant, product_id: product_2.id, price: "6.00")

      order =
        Order
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create!()

      fixture(:order_item, %{
        order_id: order.id,
        product_variant_id: product_1_product_variant_1.id,
        unit_price: product_1_product_variant_1.price,
        tax_rate: tax_rate_1.percentage,
        quantity: 2
      })

      fixture(:order_item, %{
        order_id: order.id,
        product_variant_id: product_2_product_variant_1.id,
        unit_price: product_2_product_variant_1.price,
        tax_rate: tax_rate_2.percentage,
        quantity: 1
      })

      order = Ash.load!(order, [:line_total, :line_tax_amount])

      assert Decimal.equal?(order.line_total, "86.00")
      assert Decimal.equal?(order.line_tax_amount, "21.00")
    end

    test "sums line_total and line_tax_amount correctly when promotion is applied" do
      tax_rate = fixture(:tax_rate, percentage: "0.255")
      product = fixture(:product, tax_rate_id: tax_rate.id)
      product_variant_1 = fixture(:product_variant, product_id: product.id, price: "49.99")
      product_variant_2 = fixture(:product_variant, product_id: product.id, price: "29.99")
      promotion = fixture(:promotion, discount_percentage: "0.20")

      order =
        Order
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create!()
        |> Ash.Changeset.for_update(:add_promotion, %{promotion_id: promotion.id})
        |> Ash.update!()

      fixture(:order_item, %{
        order_id: order.id,
        product_variant_id: product_variant_1.id,
        unit_price: product_variant_1.price,
        tax_rate: tax_rate.percentage,
        quantity: 1
      })

      fixture(:order_item, %{
        order_id: order.id,
        product_variant_id: product_variant_2.id,
        unit_price: product_variant_2.price,
        tax_rate: tax_rate.percentage,
        quantity: 2
      })

      order = Ash.load!(order, [:line_total, :line_tax_amount])

      assert order.line_total
             |> Decimal.round(2)
             |> Decimal.equal?("87.98")

      assert order.line_tax_amount
             |> Decimal.round(2)
             |> Decimal.equal?("22.43")
    end

    test "promotion_applied? returns true if promotion applied" do
      promotion = fixture(:promotion, discount_percentage: "0.20")

      order =
        Order
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create!()
        |> Ash.Changeset.for_update(:add_promotion, %{promotion_id: promotion.id})
        |> Ash.update!()
        |> Ash.load!(:promotion_applied?)

      assert order.promotion_applied? == true
    end

    test "promotion_applied? returns false if no promotion applied" do
      order =
        Order
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create!()
        |> Ash.load!(:promotion_applied?)

      assert order.promotion_applied? == false
    end
  end

  test "calculates total and tax_amount correctly" do
    tax_rate_2 = fixture(:tax_rate, percentage: "0.255")
    tax_rate_1 = fixture(:tax_rate, percentage: "0.15")
    product = fixture(:product, tax_rate_id: tax_rate_2.id)
    product_variant = fixture(:product_variant, product_id: product.id, price: "29.99")

    fulfillment_option =
      fixture(:fulfillment_option, %{
        name: "Pickup",
        fulfillment_method: :pickup,
        rate_type: :fixed,
        base_price: "4.99",
        # Note: using a different tax rate for fulfillment!
        tax_rate_id: tax_rate_1.id
      })

    order =
      Order
      |> Ash.Changeset.for_create(:create, %{fulfillment_option_id: fulfillment_option.id})
      |> Ash.create!()
      |> Ash.load!([:fulfillment_option])

    {:ok, fulfillment_amount} = Edenflowers.Fulfillments.calculate_price(order.fulfillment_option)

    order =
      order
      |> Ash.Changeset.for_update(:save_step_1, %{fulfillment_amount: fulfillment_amount})
      |> Ash.update!()

    _order_item =
      fixture(:order_item, %{
        order_id: order.id,
        product_variant_id: product_variant.id,
        unit_price: product_variant.price,
        tax_rate: tax_rate_2.percentage,
        quantity: 2
      })

    order = Ash.load!(order, [:total, :tax_amount])

    assert order.total
           |> Decimal.round(2)
           |> Decimal.equal?("64.97")

    assert order.tax_amount
           |> Decimal.round(2)
           |> Decimal.equal?("16.04")
  end
end
