defmodule Edenflowers.Orders.FreeDeliveryTest do
  use Edenflowers.DataCase, async: true

  import Generator
  alias Edenflowers.Orders

  setup do
    tax_rate = generate(tax_rate())

    option =
      generate(
        fulfillment_option(
          tax_rate_id: tax_rate.id,
          fulfillment_method: :delivery,
          rate_type: :dynamic,
          base_price: "4.50",
          price_per_km: "1.60",
          free_dist_km: 5,
          max_dist_km: 20
        )
      )

    free = generate(product_variant(product_id: generate(product(tax_rate_id: tax_rate.id, free_delivery: true)).id))
    paid = generate(product_variant(product_id: generate(product(tax_rate_id: tax_rate.id)).id))

    # Already quoted at the delivery step, 3 km away, for a cart without a free-delivery product.
    order =
      generate(
        order(
          state: :payment,
          fulfillment_option_id: option.id,
          fulfillment_method: :delivery,
          distance: 3000,
          fulfillment_fee: "4.50"
        )
      )

    generate(line_item(order_id: order.id, product_variant_id: paid.id))

    [order: order, free: free]
  end

  test "adding and removing a free-delivery product reprices the quoted delivery", %{order: order, free: free} do
    line_item = generate(line_item(order_id: order.id, product_variant_id: free.id))
    assert fee(order) == Decimal.new("0")

    Orders.remove_line_item!(order, line_item.id, authorize?: false)
    assert fee(order) == Decimal.new("4.50")
  end

  defp fee(order), do: Ash.reload!(order, authorize?: false).fulfillment_fee
end
