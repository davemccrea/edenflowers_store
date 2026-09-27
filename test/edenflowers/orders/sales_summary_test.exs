defmodule Edenflowers.Orders.SalesSummaryTest do
  use Edenflowers.DataCase

  import Generator

  test "sums paid orders within the date range in Helsinki time" do
    admin = generate(admin_user())
    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    variant = generate(product_variant(product_id: product.id, price: "40.00"))

    placed = fn ordered_at, payment_status, amount_paid ->
      order =
        generate(
          order(
            state: :placed,
            payment_status: payment_status,
            amount_paid: amount_paid,
            fulfillment_fee: "5.00",
            ordered_at: ordered_at
          )
        )

      generate(line_item(order_id: order.id, product_variant_id: variant.id))
    end

    # 00:30 on 1 September in Helsinki (UTC+3): inside the range
    placed.(~U[2026-08-31 21:30:00Z], :paid, "39.50")
    placed.(~U[2026-09-15 12:00:00Z], :paid, "40.00")
    placed.(~U[2026-09-15 12:00:00Z], :refunded, "40.00")
    # 00:30 on 1 October in Helsinki: outside the range
    placed.(~U[2026-09-30 21:30:00Z], :paid, "40.00")

    summary =
      Edenflowers.Orders.sales_summary!(~D[2026-09-01], ~D[2026-09-30], actor: admin)

    assert summary.order_count == 2
    assert Decimal.equal?(summary.revenue, "79.50")
  end

  test "reports zero for a range without paid orders" do
    admin = generate(admin_user())

    summary = Edenflowers.Orders.sales_summary!(~D[2026-09-01], ~D[2026-09-30], actor: admin)

    assert summary.order_count == 0
    assert Decimal.equal?(summary.revenue, 0)
  end
end
