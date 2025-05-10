defmodule Edenflowers.Fixtures do
  alias Edenflowers.Store.{TaxRate, Promotion, Product, ProductVariant, FulfillmentOption, Order, LineItem}

  def fixture(resource), do: fixture(resource, [])

  def fixture(:tax_rate, opts) do
    default_params = %{
      name: words(),
      percentage: "0.255"
    }

    params = Enum.into(opts, default_params)

    TaxRate
    |> Ash.Changeset.for_create(opts[:action] || :create, params)
    |> Ash.create!()
  end

  def fixture(:promotion, opts) do
    default_params = %{
      name: words(),
      code: "code",
      discount_percentage: "0.15",
      minimum_cart_total: "30.00",
      start_date: nil,
      expiration_date: nil
    }

    params = Enum.into(opts, default_params)

    Promotion
    |> Ash.Changeset.for_create(opts[:action] || :create, params)
    |> Ash.create!()
  end

  def fixture(:product, opts) do
    default_params = %{
      tax_rate_id: nil,
      name: words(),
      description: words(),
      image_slug: "image.png"
    }

    params = Enum.into(opts, default_params)

    Product
    |> Ash.Changeset.for_create(opts[:action] || :create, params)
    |> Ash.create!()
  end

  def fixture(:product_variant, opts) do
    default_params = %{
      product_id: nil,
      price: "35.00",
      size: :medium,
      image_slug: "image.png",
      stock_trackable: false,
      stock_quantity: 0
    }

    params = Enum.into(opts, default_params)

    ProductVariant
    |> Ash.Changeset.for_create(opts[:action] || :create, params)
    |> Ash.create!()
  end

  def fixture(:fulfillment_option, opts) do
    default_params = %{
      name: words(),
      fulfillment_method: :pickup,
      rate_type: :fixed,
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
    default_params = %{}

    params = Enum.into(opts, default_params)

    Order
    |> Ash.Changeset.for_create(opts[:action] || :create, params)
    |> Ash.create!()
  end

  def fixture(:line_item, opts) do
    default_params = %{}
    params = Enum.into(opts, default_params)

    LineItem
    |> Ash.Changeset.for_create(opts[:action] || :create, params)
    |> Ash.create!()
  end

  defp words do
    1..3
    |> Faker.Lorem.words()
    |> Enum.join(" ")
    |> String.capitalize()
  end
end
