defmodule Edenflowers.Orders.FreeDeliveryTest do
  use Edenflowers.DataCase, async: true

  import Generator
  import Mox

  alias Edenflowers.External.HereAPI
  alias Edenflowers.Orders

  setup do
    tax_rate = generate(tax_rate())
    free = generate(product_variant(product_id: generate(product(tax_rate_id: tax_rate.id, free_delivery: true)).id))
    paid = generate(product_variant(product_id: generate(product(tax_rate_id: tax_rate.id)).id))

    # Production's starting prices.
    delivery =
      generate(
        fulfillment_option(
          tax_rate_id: tax_rate.id,
          fulfillment_method: :delivery,
          rate_type: :dynamic,
          base_price: "3.00",
          price_per_km: "1.50",
          free_dist_km: 5,
          max_dist_km: 20
        )
      )

    [free: free, paid: paid, delivery: delivery]
  end

  test "a free-delivery cart pays nothing for the first 5 km, then the base price and the km beyond", ctx do
    for {metres, charged} <- [
          {4000, "0"},
          {5000, "0"},
          # 3.00 + 1.50 × 0.1
          {5100, "3.15"},
          # 3.00 + 1.50 × 1
          {6000, "4.50"},
          # 3.00 + 1.50 × 5
          {10_000, "10.50"}
        ] do
      order = delivered_to(ctx, [ctx.free, ctx.paid], metres)
      assert Decimal.equal?(fee(order), charged), "#{metres} m: charged #{fee(order)}"
    end
  end

  test "a cart without a free-delivery product pays the base price and every km", ctx do
    for {metres, charged} <- [{4000, "9.00"}, {5000, "10.50"}, {6000, "12.00"}] do
      order = delivered_to(ctx, [ctx.paid], metres)
      assert Decimal.equal?(fee(order), charged), "#{metres} m: charged #{fee(order)}"
    end
  end

  test "adding or removing the free-delivery product reprices the quoted delivery", ctx do
    order = delivered_to(ctx, [ctx.paid], 6000)
    assert Decimal.equal?(fee(order), "12.00")

    line_item = generate(line_item(order_id: order.id, product_variant_id: ctx.free.id))
    assert Decimal.equal?(fee(order), "4.50")

    Orders.remove_line_item!(order, line_item.id, authorize?: false)
    assert Decimal.equal?(fee(order), "12.00")
  end

  test "Jennie's own fee is charged whatever the cart holds", ctx do
    order = delivered_to(ctx, [ctx.free], 4000)

    Ash.Seed.update!(order, %{
      fulfillment_fee_override: Decimal.new("2.00"),
      quoted_fulfillment_fee: Decimal.new("2.00")
    })

    assert Decimal.equal?(fee(order), "2.00")
  end

  # Checks out `variants` for delivery to an address `metres` from the shop.
  defp delivered_to(ctx, variants, metres) do
    stub(HereAPI.Mock, :geocode, fn _query -> {:ok, {"Kyrkvägen 5, Vasa", "63.09,21.61", "here:1"}} end)
    stub(HereAPI.Mock, :route_distance, fn _position -> {:ok, metres} end)

    order = generate(order(state: :delivery))
    for variant <- variants, do: generate(line_item(order_id: order.id, product_variant_id: variant.id))

    order
    |> Ash.Changeset.for_update(:submit_delivery, %{
      fulfillment_option_id: ctx.delivery.id,
      fulfillment_date: Date.add(Edenflowers.ShopTime.today(), 3),
      delivery_address: "Kyrkvägen 5, Vasa",
      contact_phone_number: "045 1234567"
    })
    |> Ash.update!(authorize?: false)
  end

  defp fee(order), do: Orders.get_order_for_checkout!(order.id, authorize?: false).fulfillment_fee
end
