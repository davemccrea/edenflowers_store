defmodule Edenflowers.Orders.SalesSummaryTest do
  use Edenflowers.DataCase

  import Generator

  alias Edenflowers.Orders.Order

  test "sums paid orders within the date range in Helsinki time" do
    admin = generate(admin_user())
    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    variant = generate(product_variant(product_id: product.id, price: "40.00"))

    placed = fn ordered_at, payment_status ->
      order =
        generate(
          order(
            state: :placed,
            payment_status: payment_status,
            fulfillment_fee: "5.00",
            ordered_at: ordered_at
          )
        )

      generate(line_item(order_id: order.id, product_variant_id: variant.id))
    end

    # 00:30 on 1 September in Helsinki (UTC+3): inside the range
    placed.(~U[2026-08-31 21:30:00Z], :paid)
    placed.(~U[2026-09-15 12:00:00Z], :paid)
    placed.(~U[2026-09-15 12:00:00Z], :refunded)
    # 00:30 on 1 October in Helsinki: outside the range
    placed.(~U[2026-09-30 21:30:00Z], :paid)

    summary =
      Order
      |> Ash.ActionInput.for_action(:sales_summary, %{from: ~D[2026-09-01], to: ~D[2026-09-30]}, actor: admin)
      |> Ash.run_action!()

    assert summary.order_count == 2
    assert Decimal.equal?(summary.revenue, "90.00")
  end
end
