defmodule Edenflowers.Orders.FreeDeliveryTest do
  use Edenflowers.DataCase, async: true

  import Generator
  alias Edenflowers.Orders

  setup do
    tax_rate = generate(tax_rate())
    free = generate(product_variant(product_id: generate(product(tax_rate_id: tax_rate.id, free_delivery: true)).id))
    paid = generate(product_variant(product_id: generate(product(tax_rate_id: tax_rate.id)).id))

    [free: free, paid: paid]
  end

  describe "a delivery quoted inside the free delivery zone" do
    setup %{paid: paid} do
      order = generate(order(state: :payment, quoted_fulfillment_fee: "4.50", in_free_delivery_zone: true))
      generate(line_item(order_id: order.id, product_variant_id: paid.id))

      [order: order]
    end

    test "is free while the cart holds a free-delivery product", %{order: order, free: free} do
      assert fee(order) == Decimal.new("4.50")

      line_item = generate(line_item(order_id: order.id, product_variant_id: free.id))
      assert fee(order) == Decimal.new("0")

      Orders.remove_line_item!(order, line_item.id, authorize?: false)
      assert fee(order) == Decimal.new("4.50")
    end

    test "charges Jennie's own fee whatever the cart holds", %{order: order, free: free} do
      Ash.Seed.update!(order, %{
        fulfillment_fee_override: Decimal.new("2.00"),
        quoted_fulfillment_fee: Decimal.new("2.00")
      })

      generate(line_item(order_id: order.id, product_variant_id: free.id))

      assert fee(order) == Decimal.new("2.00")
    end
  end

  test "a delivery outside the zone is charged with a free-delivery product", %{free: free} do
    order = generate(order(state: :payment, quoted_fulfillment_fee: "8.10", in_free_delivery_zone: false))
    generate(line_item(order_id: order.id, product_variant_id: free.id))

    assert fee(order) == Decimal.new("8.10")
  end

  defp fee(order), do: Orders.get_order_for_checkout!(order.id, authorize?: false).fulfillment_fee
end
