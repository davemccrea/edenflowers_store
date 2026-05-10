defmodule Generator do
  use Ash.Generator

  alias Edenflowers.Store.{
    TaxRate,
    Promotion,
    ProductCategory,
    Product,
    ProductVariant,
    Cart,
    CartLineItem,
    Order,
    OrderLineItem,
    FulfillmentOption
  }

  def tax_rate(opts \\ []) do
    changeset_generator(
      TaxRate,
      :create,
      defaults: %{
        name: sequence(:tax_rate_name, &"Tax Rate #{&1}"),
        percentage: "0.255"
      },
      overrides: opts,
      authorize?: false
    )
  end

  def promotion(opts \\ []) do
    changeset_generator(
      Promotion,
      :create,
      defaults: %{
        name: words(),
        code: sequence(:promotion_code, &"PROMO-#{&1}"),
        discount_percentage: "0.20",
        minimum_cart_total: "0",
        start_date: nil,
        expiration_date: nil,
        usage_limit: nil
      },
      overrides: opts,
      authorize?: false
    )
  end

  def product_category(opts \\ []) do
    changeset_generator(ProductCategory, :create,
      defaults: %{
        name: words()
      },
      overrides: opts,
      authorize?: false
    )
  end

  def product(opts \\ []) do
    tax_rate_id = opts[:tax_rate_id] || once(:default_tax_rate_id, fn -> generate(tax_rate()).id end)

    product_category_id =
      opts[:product_category_id] || once(:default_product_category_id, fn -> generate(product_category()).id end)

    changeset_generator(Product, :create,
      defaults: %{
        product_category_id: product_category_id,
        tax_rate_id: tax_rate_id,
        name: sequence(:product_name, &"Product #{&1}"),
        description: words(),
        image_slug: "image.png"
      },
      overrides: opts,
      authorize?: false
    )
  end

  def product_variant(opts \\ []) do
    changeset_generator(ProductVariant, :create,
      defaults: %{
        price: "35.00",
        size: :medium,
        image_slug: "image.png",
        stock_trackable: false,
        stock_quantity: 0
      },
      overrides: opts,
      authorize?: false
    )
  end

  def cart(opts \\ []) do
    # seed_generator (vs changeset_generator) so tests can set internal
    # attributes like fulfillment_amount, payment_intent_id, promotion_id.
    seed_generator(
      %Cart{
        state: :contact_details,
        order_reference: :crypto.strong_rand_bytes(6) |> Base.encode16()
      },
      overrides: opts,
      authorize?: false
    )
  end

  def cart_line_item(opts \\ []) do
    changeset_generator(CartLineItem, :add_to_cart,
      defaults: %{
        quantity: 1,
        is_card: false
      },
      overrides: opts,
      authorize?: false
    )
  end

  # A *placed* order. Bypasses the conversion flow — sets every snapshot
  # field directly. Use cart() + Cart.convert when you want to exercise the
  # conversion itself.
  def order(opts \\ []) do
    seed_generator(
      %Order{
        order_reference: :crypto.strong_rand_bytes(6) |> Base.encode16(),
        ordered_at: DateTime.utc_now(),
        payment_status: :paid,
        fulfillment_status: :pending,
        payment_intent_id: "pi_test_#{:rand.uniform(1_000_000)}",
        customer_name: "Test Customer",
        customer_email: "test@example.com",
        gift: false,
        locale: "sv-FI",
        line_total: Decimal.new("0"),
        line_tax_amount: Decimal.new("0"),
        discount_amount: Decimal.new("0"),
        fulfillment_tax_amount: Decimal.new("0"),
        tax_amount: Decimal.new("0"),
        total: Decimal.new("0")
      },
      overrides: opts,
      authorize?: false
    )
  end

  def order_line_item(opts \\ []) do
    changeset_generator(OrderLineItem, :snapshot_from_cart,
      defaults: %{
        quantity: 1,
        is_card: false,
        line_total: Decimal.new("0"),
        discount_amount: Decimal.new("0"),
        line_tax_amount: Decimal.new("0")
      },
      overrides: opts,
      authorize?: false
    )
  end

  def fulfillment_option(opts \\ []) do
    tax_rate_id = opts[:tax_rate_id] || once(:default_tax_rate_id, fn -> generate(tax_rate()).id end)

    changeset_generator(FulfillmentOption, :create,
      defaults: %{
        tax_rate_id: tax_rate_id,
        name: sequence(:fulfillment_option_name, &"Fulfillment Option #{&1}"),
        fulfillment_method: :pickup,
        rate_type: :fixed,
        minimum_cart_total: 0,
        base_price: "4.50",
        price_per_km: "1.60",
        free_dist_km: 5,
        max_dist_km: 20,
        same_day: true,
        order_deadline: ~T[14:00:00],
        available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday, :sunday],
        enabled_dates: [],
        disabled_dates: []
      },
      overrides: opts,
      authorize?: false
    )
  end

  defp words do
    1..3
    |> Faker.Lorem.words()
    |> Enum.join(" ")
    |> String.capitalize()
  end
end
