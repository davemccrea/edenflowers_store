defmodule Edenflowers.Orders.SalesSummaryTest do
  use Edenflowers.DataCase, async: true

  import Generator

  test "sums paid orders within the date range in Helsinki time" do
    admin = generate(admin_user())
    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    variant = generate(product_variant(product_id: product.id, price: "40.00"))

    placed = fn ordered_at, payments ->
      order = generate(order(state: :placed, quoted_fulfillment_fee: "5.00", ordered_at: ordered_at))

      generate(line_item(order_id: order.id, product_variant_id: variant.id))

      for {paid_at, amount} <- payments do
        generate(payment(order_id: order.id, amount: Decimal.new(amount), paid_at: paid_at))
      end
    end

    # 00:30 on 1 September in Helsinki (UTC+3): inside the range
    placed.(~U[2026-08-31 21:30:00Z], [{~U[2026-08-31 21:30:00Z], "45.00"}])
    placed.(~U[2026-09-15 12:00:00Z], [{~U[2026-09-15 12:00:00Z], "45.00"}])
    # Edited after payment to owe more: still a sale.
    placed.(~U[2026-09-15 12:00:00Z], [{~U[2026-09-15 12:00:00Z], "30.00"}])
    # Paid and refunded in the range: counts nothing.
    placed.(~U[2026-09-15 12:00:00Z], [
      {~U[2026-09-15 12:00:00Z], "45.00"},
      {~U[2026-09-16 12:00:00Z], "-45.00"}
    ])

    # 00:30 on 1 October in Helsinki: outside the range
    placed.(~U[2026-09-30 21:30:00Z], [{~U[2026-09-30 21:30:00Z], "45.00"}])
    # Placed in August, its balance paid in September: the money counts in September.
    placed.(~U[2026-08-20 12:00:00Z], [
      {~U[2026-08-20 12:00:00Z], "40.00"},
      {~U[2026-09-10 12:00:00Z], "4.00"}
    ])

    summary =
      Edenflowers.Orders.sales_summary!(~D[2026-09-01], ~D[2026-09-30], actor: admin)

    assert summary.order_count == 3
    assert Decimal.equal?(summary.revenue, "124.00")
  end

  test "reports zero for a range without paid orders" do
    admin = generate(admin_user())

    summary = Edenflowers.Orders.sales_summary!(~D[2026-09-01], ~D[2026-09-30], actor: admin)

    assert summary.order_count == 0
    assert Decimal.equal?(summary.revenue, 0)
  end
end
