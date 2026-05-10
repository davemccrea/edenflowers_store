defmodule Edenflowers.Store.SnapshotAndLockdownTest do
  @moduledoc "Covers the invariants from ADR-0001."

  use Edenflowers.DataCase
  import Generator
  alias Edenflowers.Store.{Order, LineItem}

  defp seeded_order_in_payment(opts \\ []) do
    tax_rate = generate(tax_rate(percentage: "0.255"))
    product = generate(product(tax_rate_id: tax_rate.id))
    variant = generate(product_variant(product_id: product.id, price: "40.00"))
    fulfillment_option = generate(fulfillment_option(tax_rate_id: tax_rate.id))
    {:ok, fulfillment_amount} = Edenflowers.Fulfillments.calculate_price(fulfillment_option)

    order_attrs =
      Keyword.merge(
        [
          state: :payment,
          customer_name: "Jane Doe",
          customer_email: "jane@example.com",
          fulfillment_option_id: fulfillment_option.id,
          fulfillment_method: :pickup,
          fulfillment_date: Date.utc_today(),
          fulfillment_amount: fulfillment_amount,
          fulfillment_tax_rate: tax_rate.percentage,
          payment_intent_id: "pi_test_#{:rand.uniform(1_000_000)}"
        ],
        opts
      )

    order = generate(order(order_attrs))

    _line_item =
      generate(
        line_item(
          order_id: order.id,
          product_variant_id: variant.id,
          quantity: 2
        )
      )

    %{
      order: order,
      tax_rate: tax_rate,
      product: product,
      variant: variant,
      fulfillment_option: fulfillment_option
    }
  end

  describe "fulfillment_tax_rate denormalisation" do
    test "submit_delivery captures fulfillment_option.tax_rate.percentage onto the order" do
      tax_rate = generate(tax_rate(percentage: "0.255"))
      product = generate(product(tax_rate_id: tax_rate.id))
      _variant = generate(product_variant(product_id: product.id))
      fulfillment_option = generate(fulfillment_option(tax_rate_id: tax_rate.id))

      order = generate(order(state: :delivery, fulfillment_option_id: fulfillment_option.id, fulfillment_method: :pickup))

      assert {:ok, order} =
               order
               |> Ash.Changeset.for_update(:submit_delivery, %{
                 fulfillment_option_id: fulfillment_option.id,
                 fulfillment_date: Date.utc_today()
               })
               |> Ash.update(authorize?: false)

      assert Decimal.equal?(order.fulfillment_tax_rate, tax_rate.percentage)
    end

    test "later edits to the tax_rate row do not change the order's captured rate" do
      tax_rate = generate(tax_rate(percentage: "0.255"))
      product = generate(product(tax_rate_id: tax_rate.id))
      _variant = generate(product_variant(product_id: product.id))
      fulfillment_option = generate(fulfillment_option(tax_rate_id: tax_rate.id))

      order = generate(order(state: :delivery, fulfillment_option_id: fulfillment_option.id, fulfillment_method: :pickup))

      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:submit_delivery, %{
          fulfillment_option_id: fulfillment_option.id,
          fulfillment_date: Date.utc_today()
        })
        |> Ash.update(authorize?: false)

      original_rate = order.fulfillment_tax_rate

      # TaxRate has no generic :update action; bypass via Ash.Seed.
      Ash.Seed.update!(tax_rate, %{percentage: Decimal.new("0.30")})

      reloaded = Order.get_by_id!(order.id, authorize?: false)
      assert Decimal.equal?(reloaded.fulfillment_tax_rate, original_rate)
    end
  end

  describe "SnapshotTotals at finalize_checkout" do
    test "captures placed_total, placed_tax_amount, placed_*  onto the order" do
      %{order: order} = seeded_order_in_payment()

      assert {:ok, placed} = Order.finalize_checkout(order.id, authorize?: false)

      assert placed.state == :placed
      assert %Decimal{} = placed.placed_line_total
      assert %Decimal{} = placed.placed_line_tax_amount
      assert %Decimal{} = placed.placed_discount_amount
      assert %Decimal{} = placed.placed_fulfillment_tax_amount
      assert %Decimal{} = placed.placed_tax_amount
      assert %Decimal{} = placed.placed_total
    end

    test "captures placed_promotion_code from the active promotion" do
      promotion = generate(promotion(code: "SPRING-25", discount_percentage: "0.10"))
      %{order: order} = seeded_order_in_payment(promotion_id: promotion.id)

      assert {:ok, placed} = Order.finalize_checkout(order.id, authorize?: false)
      assert placed.placed_promotion_code == "SPRING-25"
    end

    test "later edits to the promotion's code do not change the snapshot" do
      promotion = generate(promotion(code: "SPRING-25", discount_percentage: "0.10"))
      %{order: order} = seeded_order_in_payment(promotion_id: promotion.id)

      {:ok, placed} = Order.finalize_checkout(order.id, authorize?: false)
      assert placed.placed_promotion_code == "SPRING-25"

      Ash.Seed.update!(promotion, %{code: "SUMMER-30"})

      reloaded = Order.get_by_id!(placed.id, authorize?: false)
      assert reloaded.placed_promotion_code == "SPRING-25"
    end

    test "captures per-line-item placed_* values" do
      %{order: order} = seeded_order_in_payment()

      assert {:ok, placed} = Order.finalize_checkout(order.id, authorize?: false)

      placed = Ash.load!(placed, :line_items, authorize?: false)
      assert [item | _] = placed.line_items
      assert %Decimal{} = item.placed_line_total
      assert %Decimal{} = item.placed_discount_amount
      assert %Decimal{} = item.placed_line_tax_amount
    end
  end

  describe "Order policy lockdown after :placed" do
    setup do
      %{order: order} = seeded_order_in_payment()
      {:ok, placed} = Order.finalize_checkout(order.id, authorize?: false)
      %{placed: placed}
    end

    test "rejects update_fulfillment_option on a placed order", %{placed: placed} do
      option = generate(fulfillment_option())

      assert {:error, %Ash.Error.Forbidden{}} =
               Order.update_fulfillment_option(placed, option.id)
    end

    test "rejects set_gift on a placed order", %{placed: placed} do
      assert {:error, %Ash.Error.Forbidden{}} = Order.set_gift(placed, true)
    end

    test "rejects clear_promotion on a placed order", %{placed: placed} do
      assert {:error, %Ash.Error.Forbidden{}} = Order.clear_promotion(placed)
    end

    test "rejects restart_checkout on a placed order", %{placed: placed} do
      assert {:error, %Ash.Error.Forbidden{}} = Order.restart_checkout(placed)
    end

    test "rejects mark_payment_failed on a placed order", %{placed: placed} do
      assert {:error, %Ash.Error.Forbidden{}} = Order.mark_payment_failed(placed)
    end

    test "rejects a second finalize_checkout", %{placed: placed} do
      # Already :placed — finalize_checkout requires :payment.
      assert {:error, %Ash.Error.Forbidden{}} = Order.finalize_checkout(placed.id)
    end
  end

  describe "LineItem policy lockdown after parent :placed" do
    setup do
      %{order: order, variant: variant} = seeded_order_in_payment()
      {:ok, placed} = Order.finalize_checkout(order.id, authorize?: false)
      placed = Ash.load!(placed, :line_items, authorize?: false)
      %{placed: placed, variant: variant, line_item: hd(placed.line_items)}
    end

    test "rejects creating a new line item on a placed order", %{placed: placed, variant: variant} do
      assert {:error, %Ash.Error.Forbidden{}} =
               LineItem.add_item(%{
                 order_id: placed.id,
                 product_variant_id: variant.id,
                 quantity: 1
               })
    end

    test "rejects increment_quantity on a placed order's line item", %{line_item: item} do
      assert {:error, %Ash.Error.Forbidden{}} = LineItem.increment_quantity(item)
    end

    test "rejects decrement_quantity on a placed order's line item", %{line_item: item} do
      assert {:error, %Ash.Error.Forbidden{}} = LineItem.decrement_quantity(item)
    end

    test "rejects remove_item on a placed order's line item", %{line_item: item} do
      assert {:error, %Ash.Error.Forbidden{}} = LineItem.remove_item(item)
    end
  end
end
