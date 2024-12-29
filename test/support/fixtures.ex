defmodule Edenflowers.Fixtures do
  alias Edenflowers.Store.{TaxRate, Promotion, Product, ProductVariant, FulfillmentOption, Order, LineItem}

  def fixture(resource), do: fixture(resource, [])

  def fixture(:tax_rate, opts) do
    TaxRate
    |> Ash.Changeset.for_create(opts[:acton] || :create, %{
      name: opts[:name] || words(),
      percentage: opts[:percentage] || "0.255"
    })
    |> Ash.create!()
  end

  def fixture(:promotion, opts) do
    Promotion
    |> Ash.Changeset.for_create(opts[:action] || :create, %{
      name: opts[:name] || words(),
      code: opts[:code] || "code",
      discount_percentage: opts[:discount_percentage] || "0.15",
      minimum_cart_total: opts[:minimum_cart_total] || "30.00",
      start_date: opts[:start_date],
      expiration_date: opts[:expiration_date]
    })
    |> Ash.create!()
  end

  def fixture(:product, opts) do
    Product
    |> Ash.Changeset.for_create(opts[:action] || :create, %{
      tax_rate_id: opts[:tax_rate_id],
      name: opts[:name] || words(),
      description: opts[:description] || words()
    })
    |> Ash.create!()
  end

  def fixture(:product_variant, opts) do
    ProductVariant
    |> Ash.Changeset.for_create(opts[:action] || :create, %{
      product_id: opts[:product_id],
      price: opts[:price] || "35.00",
      size: opts[:size] || :medium,
      image: "image.png",
      stock_trackable: false,
      stock_quantity: 0
    })
    |> Ash.create!()
  end

  def fixture(:fulfillment_option, opts) do
    default_params = %{
      name: words(),
      type: :fixed,
      minimum_cart_total: 0,
      base_price: "4.50",
      price_per_km: "1.60",
      free_dist_km: 5,
      max_dist_km: 20,
      same_day: true,
      order_deadline: ~T[14:00:00],
      monday: true,
      tuesday: true,
      wednesday: true,
      thursday: true,
      friday: true,
      saturday: true,
      sunday: true,
      enabled_dates: [],
      disabled_dates: []
    }

    params = Enum.into(opts, default_params)

    FulfillmentOption
    |> Ash.Changeset.for_create(opts[:create] || :create, params)
    |> Ash.create!()
  end

  def fixture(:order, opts) do
    Order
    |> Ash.Changeset.for_create(opts[:action] || :create, %{
      promotion_id: opts[:promotion_id]
    })
    |> Ash.create!()
  end

  def fixture(:order_item, opts) do
    LineItem
    |> Ash.Changeset.for_create(opts[:action] || :create, %{
      order_id: opts[:order_id],
      product_variant_id: opts[:product_variant_id],
      unit_price: opts[:unit_price],
      quantity: opts[:quantity],
      tax_rate: opts[:tax_rate]
    })
    |> Ash.create!()
  end

  defp words do
    1..3
    |> Faker.Lorem.words()
    |> Enum.join(" ")
    |> String.capitalize()
  end
end
