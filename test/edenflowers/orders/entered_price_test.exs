defmodule Edenflowers.Orders.EnteredPriceTest do
  use Edenflowers.DataCase, async: true

  import Generator
  import Mox

  alias Edenflowers.External.HereAPI
  alias Edenflowers.Fulfillment.Fee
  alias Edenflowers.Orders
  alias Edenflowers.Orders.EnteredPrice

  setup :verify_on_exit!

  setup do
    flowers = generate(tax_rate(percentage: "0.255"))
    reduced = generate(tax_rate(percentage: "0.14"))
    product = generate(product(tax_rate_id: flowers.id, name: "Spring Bouquet", free_delivery: false))
    variant = generate(product_variant(product_id: product.id, price: "49.00"))
    card_product = generate(product(tax_rate_id: flowers.id, name: "Thank you", free_delivery: false))
    card = generate(product_variant(product_id: card_product.id, price: "3.00", size: :small))

    pickup = generate(fulfillment_option(tax_rate_id: flowers.id, fulfillment_method: :pickup, base_price: "0.00"))

    delivery =
      generate(
        fulfillment_option(
          tax_rate_id: flowers.id,
          fulfillment_method: :delivery,
          rate_type: :dynamic,
          base_price: "5.00",
          price_per_km: "1.00",
          free_dist_km: 2,
          max_dist_km: 20
        )
      )

    %{
      admin: generate(admin_user()),
      flowers: flowers,
      reduced: reduced,
      variant: variant,
      card: card,
      pickup: pickup,
      delivery: delivery
    }
  end

  defp params(ctx, overrides) do
    Map.merge(
      %{
        "customer_name" => "Mrs Holm",
        "customer_phone_number" => "040 123 4567",
        "locale" => "sv-FI",
        "fulfillment_option_id" => ctx.pickup.id,
        "fulfillment_date" => Date.to_iso8601(Date.add(Edenflowers.ShopTime.today(), 1)),
        "gift" => "false",
        "line_items" => [
          %{"kind" => "catalogue", "product_variant_id" => ctx.variant.id, "quantity" => "2"},
          %{
            "kind" => "custom",
            "product_name" => "Funeral spray",
            "unit_price" => "85,50",
            "tax_rate_id" => ctx.reduced.id,
            "quantity" => "1"
          }
        ]
      },
      overrides
    )
  end

  # The price shown before saving is the one the saved order has.
  defp assert_priced_as_saved(price, order) do
    order = Ash.load!(order, [:grand_total, :vat, :fulfillment_fee], authorize?: false)

    assert Decimal.equal?(price.total, order.grand_total)
    assert Decimal.equal?(price.vat, order.vat)
    assert Decimal.equal?(price.fulfillment_fee, order.fulfillment_fee)
  end

  # As the form's quote, looked up when the address is typed.
  defp delivery_quote(option, distance_m) do
    %{fulfillment_fee: fee, in_free_delivery_zone: in_zone} = Fee.calculate(option, distance_m)
    %{fee: fee, in_free_delivery_zone: in_zone}
  end

  defp stub_distance(distance_m) do
    stub(HereAPI.Mock, :geocode, fn _query -> {:ok, {"Kyrkvägen 5, Vasa", "63.09,21.61", "here:1"}} end)
    stub(HereAPI.Mock, :route_distance, fn _position -> {:ok, distance_m} end)
  end

  test "prices catalogue, custom and card lines and pickup as saving does", ctx do
    params = params(ctx, %{"gift" => "true", "recipient_name" => "Ada", "card_variant_id" => ctx.card.id})

    price = EnteredPrice.calculate(nil, params, nil)
    {:ok, order} = Orders.place_custom_order(params, actor: ctx.admin)

    assert [
             %{name: "Spring Bouquet", quantity: 2, total: bouquets},
             %{name: "Funeral spray", total: spray},
             %{name: "Thank you", total: card}
           ] = price.lines

    assert Decimal.equal?(bouquets, "98.00")
    assert Decimal.equal?(spray, "85.50")
    assert Decimal.equal?(card, "3.00")
    assert Decimal.equal?(price.total, "186.50")
    assert_priced_as_saved(price, order)
  end

  test "charges a delivery by the quote", ctx do
    stub_distance(5000)
    params = params(ctx, %{"fulfillment_option_id" => ctx.delivery.id, "delivery_address" => "Kyrkvägen 5"})

    price = EnteredPrice.calculate(nil, params, delivery_quote(ctx.delivery, 5000))
    {:ok, order} = Orders.place_custom_order(params, actor: ctx.admin)

    assert Decimal.equal?(price.fulfillment_fee, "10.00")
    assert_priced_as_saved(price, order)
  end

  test "waives delivery in the free zone for a free-delivery product", ctx do
    stub_distance(1000)
    free = generate(product(tax_rate_id: ctx.flowers.id, free_delivery: true))
    free_variant = generate(product_variant(product_id: free.id, price: "60.00"))

    params =
      params(ctx, %{
        "fulfillment_option_id" => ctx.delivery.id,
        "delivery_address" => "Kyrkvägen 5",
        "line_items" => [%{"kind" => "catalogue", "product_variant_id" => free_variant.id, "quantity" => "1"}]
      })

    price = EnteredPrice.calculate(nil, params, delivery_quote(ctx.delivery, 1000))
    {:ok, order} = Orders.place_custom_order(params, actor: ctx.admin)

    assert price.free_delivery?
    assert Decimal.equal?(price.fulfillment_fee, "0")
    assert_priced_as_saved(price, order)
  end

  test "charges Jennie's own fee as she set it", ctx do
    params = params(ctx, %{"fulfillment_fee_override" => "12.50"})

    price = EnteredPrice.calculate(nil, params, nil)
    {:ok, order} = Orders.place_custom_order(params, actor: ctx.admin)

    assert Decimal.equal?(price.fulfillment_fee, "12.50")
    assert_priced_as_saved(price, order)
  end

  test "an edit keeps a line's sold price and the order's fee, as saving does", ctx do
    stub_distance(5000)
    params = params(ctx, %{"fulfillment_option_id" => ctx.delivery.id, "delivery_address" => "Kyrkvägen 5"})
    {:ok, order} = Orders.place_custom_order(params, actor: ctx.admin)

    Ash.Changeset.for_update(ctx.variant, :update, %{price: "55.00"}) |> Ash.update!(authorize?: false)
    Ash.Changeset.for_update(ctx.delivery, :update, %{base_price: "9.00"}) |> Ash.update!(authorize?: false)

    order = Orders.get_order_for_admin!(order.id, actor: ctx.admin)
    bouquet = Enum.find(order.line_items, & &1.product_variant_id)

    edit =
      Map.merge(params, %{
        "line_items" => [%{"id" => bouquet.id, "quantity" => "3"}],
        "fulfillment_option_id" => ctx.delivery.id
      })

    price = EnteredPrice.calculate(order, edit, nil)
    {:ok, edited} = Orders.edit_order(order, edit, actor: ctx.admin)

    assert [%{name: "Spring Bouquet", quantity: 3, total: total}] = price.lines
    assert Decimal.equal?(total, "147.00")
    assert_priced_as_saved(price, edited)
  end

  test "leaves out lines not filled in, and the fee until it can be priced", ctx do
    params =
      params(ctx, %{
        "fulfillment_option_id" => ctx.delivery.id,
        "delivery_address" => "",
        "line_items" => [
          %{"kind" => "catalogue", "product_variant_id" => ctx.variant.id, "quantity" => "1"},
          %{"kind" => "catalogue", "product_variant_id" => "", "quantity" => "1"},
          %{"kind" => "custom", "product_name" => "Wreath", "unit_price" => "", "quantity" => "1"}
        ]
      })

    price = EnteredPrice.calculate(nil, params, nil)

    assert [%{name: "Spring Bouquet"}] = price.lines
    assert price.fulfillment_fee == nil
    assert Decimal.equal?(price.total, "49.00")
  end
end
