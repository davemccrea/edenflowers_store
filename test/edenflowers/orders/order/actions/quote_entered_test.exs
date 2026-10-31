defmodule Edenflowers.Orders.Order.Actions.QuoteEnteredTest do
  use Edenflowers.DataCase, async: true

  import Generator
  import Mox

  alias Edenflowers.External.HereAPI
  alias Edenflowers.Fulfillment.Fee
  alias Edenflowers.Orders

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
    %{fulfillment_fee: fee, free_delivery_fee: free_delivery_fee} = Fee.calculate(option, distance_m)
    %{fee: fee, free_delivery_fee: free_delivery_fee}
  end

  defp stub_distance(distance_m) do
    stub(HereAPI.Mock, :geocode, fn _query -> {:ok, {"Kyrkvägen 5, Vasa", "63.09,21.61", "here:1"}} end)
    stub(HereAPI.Mock, :route_distance, fn _position -> {:ok, distance_m} end)
  end

  test "prices catalogue, custom and card lines and pickup as saving does", ctx do
    params = params(ctx, %{"gift" => "true", "recipient_name" => "Ada", "card_variant_id" => ctx.card.id})

    price = Orders.quote_entered_order!(nil, params, nil, actor: ctx.admin)
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

    price = Orders.quote_entered_order!(nil, params, delivery_quote(ctx.delivery, 5000), actor: ctx.admin)
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

    price = Orders.quote_entered_order!(nil, params, delivery_quote(ctx.delivery, 1000), actor: ctx.admin)
    {:ok, order} = Orders.place_custom_order(params, actor: ctx.admin)

    assert price.free_delivery?
    assert Decimal.equal?(price.fulfillment_fee, "0")
    assert_priced_as_saved(price, order)
  end

  test "past the free distance charges a free-delivery product the base price and the km beyond", ctx do
    stub_distance(3500)
    free = generate(product(tax_rate_id: ctx.flowers.id, free_delivery: true))
    free_variant = generate(product_variant(product_id: free.id, price: "60.00"))

    params =
      params(ctx, %{
        "fulfillment_option_id" => ctx.delivery.id,
        "delivery_address" => "Kyrkvägen 5",
        "line_items" => [%{"kind" => "catalogue", "product_variant_id" => free_variant.id, "quantity" => "1"}]
      })

    price = Orders.quote_entered_order!(nil, params, delivery_quote(ctx.delivery, 3500), actor: ctx.admin)
    {:ok, order} = Orders.place_custom_order(params, actor: ctx.admin)

    # 5.00 + 1.00 × (3.5 − 2), rather than 8.50 for every km
    assert Decimal.equal?(price.fulfillment_fee, "6.50")
    assert_priced_as_saved(price, order)
  end

  test "charges Jennie's own fee as she set it", ctx do
    params = params(ctx, %{"fulfillment_fee_override" => "12.50"})

    price = Orders.quote_entered_order!(nil, params, nil, actor: ctx.admin)
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

    price = Orders.quote_entered_order!(order, edit, nil, actor: ctx.admin)
    {:ok, edited} = Orders.edit_order(order, edit, actor: ctx.admin)

    assert [%{name: "Spring Bouquet", quantity: 3, total: total}] = price.lines
    assert Decimal.equal?(total, "147.00")
    assert_priced_as_saved(price, edited)
  end

  test "an edit that drops Jennie's own fee prices the stored distance, as saving does", ctx do
    stub_distance(5000)

    params =
      params(ctx, %{
        "fulfillment_option_id" => ctx.delivery.id,
        "delivery_address" => "Kyrkvägen 5",
        "fulfillment_fee_override" => "12.50"
      })

    {:ok, order} = Orders.place_custom_order(params, actor: ctx.admin)
    order = Orders.get_order_for_admin!(order.id, actor: ctx.admin)
    edit = Map.put(params, "fulfillment_fee_override", "")

    price = Orders.quote_entered_order!(order, edit, nil, actor: ctx.admin)
    {:ok, edited} = Orders.edit_order(order, edit, actor: ctx.admin)

    assert Decimal.equal?(price.fulfillment_fee, "10.00")
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

    price = Orders.quote_entered_order!(nil, params, nil, actor: ctx.admin)

    assert [%{name: "Spring Bouquet"}] = price.lines
    assert price.fulfillment_fee == nil
    assert Decimal.equal?(price.total, "49.00")
  end

  test "saves, stocks and emails nothing", ctx do
    stocked = generate(product_variant(product_id: ctx.variant.product_id, size: :large, stock_quantity: 5))

    params =
      params(ctx, %{
        "customer_email" => "holm@example.com",
        "line_items" => [%{"kind" => "catalogue", "product_variant_id" => stocked.id, "quantity" => "2"}]
      })

    Orders.quote_entered_order!(nil, params, nil, actor: ctx.admin)

    assert Ash.read!(Orders.Order, authorize?: false) == []
    assert Ash.get!(Edenflowers.Catalog.ProductVariant, stocked.id, authorize?: false).stock_quantity == 5

    refute Enum.any?(
             Ash.read!(Edenflowers.Accounts.User, authorize?: false),
             &(to_string(&1.email) == "holm@example.com")
           )

    assert all_enqueued() == []
  end

  describe "an order with a promotion" do
    # 15 % off from 20.00. Each line's discount is rounded to cents on its
    # own: 1.50 off each 10.03, where the whole 20.06 would take 3.01 off.
    setup ctx do
      product = generate(product(tax_rate_id: ctx.flowers.id, name: "Posy", free_delivery: false))
      posy = generate(product_variant(product_id: product.id, price: "10.03"))

      custom = %{
        "kind" => "custom",
        "product_name" => "Buttonhole",
        "unit_price" => "10,03",
        "tax_rate_id" => ctx.reduced.id,
        "quantity" => "1"
      }

      posy_params = %{"kind" => "catalogue", "product_variant_id" => posy.id, "quantity" => "1"}
      params = params(ctx, %{"line_items" => [posy_params, custom]})
      {:ok, order} = Orders.place_custom_order(params, actor: ctx.admin)

      promotion = generate(promotion(discount_rate: "0.15", minimum_cart_total: "20.00"))

      Ash.Seed.update!(order, %{
        promotion_id: promotion.id,
        discount_rate: Decimal.new("0.15"),
        promotion_minimum_cart_total: Decimal.new("20.00")
      })

      order = Orders.get_order_for_admin!(order.id, actor: ctx.admin)
      posy_line = Enum.find(order.line_items, & &1.product_variant_id)

      %{order: order, params: params, kept_posy: %{"id" => posy_line.id, "quantity" => "1"}, custom: custom}
    end

    test "discounts an edit that meets the minimum, line by line", ctx do
      edit = Map.put(ctx.params, "line_items", [ctx.kept_posy, ctx.custom])

      price = Orders.quote_entered_order!(ctx.order, edit, nil, actor: ctx.admin)
      {:ok, edited} = Orders.edit_order(ctx.order, edit, actor: ctx.admin)

      assert Decimal.equal?(price.total, "17.06")
      assert_priced_as_saved(price, edited)
    end

    test "leaves an edit below the minimum undiscounted", ctx do
      edit = Map.put(ctx.params, "line_items", [ctx.kept_posy])

      price = Orders.quote_entered_order!(ctx.order, edit, nil, actor: ctx.admin)
      {:ok, edited} = Orders.edit_order(ctx.order, edit, actor: ctx.admin)

      assert Decimal.equal?(price.total, "10.03")
      assert_priced_as_saved(price, edited)
    end
  end
end
