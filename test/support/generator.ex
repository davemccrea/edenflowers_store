defmodule Generator do
  use Ash.Generator

  alias Edenflowers.Store.{
    TaxRate,
    Promotion,
    ProductCategory,
    Product,
    ProductVariant,
    Order,
    LineItem,
    FulfillmentOption
  }

  def tax_rate(opts \\ []) do
    changeset_generator(
      TaxRate,
      :create,
      defaults: %{name: words()},
      overrides: opts
    )
  end

  def promotion(opts \\ []) do
    changeset_generator(
      Promotion,
      :create,
      defaults: %{
        name: words(),
        code: "PROMO-#{Faker.random_between(100_000, 999_999)}",
        discount_percentage: "0.20"
      },
      overrides: opts
    )
  end

  def product_category(opts \\ []) do
    changeset_generator(ProductCategory, :create,
      defaults: %{
        name: words()
      },
      overrides: opts
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
        name: words(),
        description: words(),
        image_slug: "image.png"
      },
      overrides: opts
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
      overrides: opts
    )
  end

  def order(opts \\ []) do
    changeset_generator(Order, :create, overrides: opts)
  end

  def line_item(opts \\ []) do
    changeset_generator(LineItem, :create, defaults: %{}, overrides: opts)
  end

  def fulfillment_option(opts \\ []) do
    tax_rate_id = opts[:tax_rate_id] || once(:default_tax_rate_id, fn -> generate(tax_rate()).id end)

    changeset_generator(FulfillmentOption, :create,
      defaults: %{
        tax_rate_id: tax_rate_id
      },
      overrides: opts
    )
  end

  defp words do
    1..3
    |> Faker.Lorem.words()
    |> Enum.join(" ")
    |> String.capitalize()
  end
end
