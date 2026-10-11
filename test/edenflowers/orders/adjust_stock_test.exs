defmodule Edenflowers.Orders.AdjustStockTest do
  use Edenflowers.DataCase, async: true

  import ExUnit.CaptureLog
  import Generator

  alias Edenflowers.Catalog.ProductVariant
  alias Edenflowers.Orders

  setup do
    tax_rate = generate(tax_rate())
    %{product: generate(product(tax_rate_id: tax_rate.id))}
  end

  defp place_online_order(lines) do
    order = generate(order(state: :payment, payment_intent_id: "pi_test"))

    for {variant, quantity} <- lines do
      generate(line_item(order_id: order.id, product_variant_id: variant.id, quantity: quantity))
    end

    order = Ash.load!(order, :grand_total, authorize?: false)

    {:ok, order} =
      Orders.finalize_checkout(order.id, order.payment_intent_id, %{amount_paid: order.grand_total}, authorize?: false)

    order
  end

  defp stock(variant), do: Ash.get!(ProductVariant, variant.id, authorize?: false).stock_quantity

  test "placing an Online Order takes its tracked sizes off the shelf", %{product: product} do
    tracked = generate(product_variant(product_id: product.id, size: :small, stock_quantity: 3))
    unlimited = generate(product_variant(product_id: product.id, size: :large))

    place_online_order([{tracked, 2}, {unlimited, 4}])

    assert stock(tracked) == 1
    assert stock(unlimited) == nil
  end

  test "an oversold Online Order is placed, stock stops at 0 and the oversell is logged", %{product: product} do
    tracked = generate(product_variant(product_id: product.id, stock_quantity: 1))

    log =
      capture_log(fn ->
        assert %{state: :placed} = place_online_order([{tracked, 2}])
      end)

    assert stock(tracked) == 0
    assert log =~ "took 2 of variant #{tracked.id} with only 1 in stock"
  end
end
