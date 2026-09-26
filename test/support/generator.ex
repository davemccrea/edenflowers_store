defmodule Generator do
  use Ash.Generator

  alias Edenflowers.Accounts.User
  alias Edenflowers.Orders.Order.Changes.GenerateOrderReference

  alias Edenflowers.Pricing.{TaxRate, Promotion}
  alias Edenflowers.Catalog.{ProductCategory, Product, ProductVariant}
  alias Edenflowers.Orders.{Order, LineItem}
  alias Edenflowers.Fulfillment.FulfillmentOption
  alias Edenflowers.Courses.{Course, CourseRegistration}

  # seed_generator bypasses actions so we can set :admin directly
  # (the attribute is writable?: false on the resource).
  def admin_user(opts \\ []) do
    seed_generator(
      %User{
        email: StreamData.repeatedly(fn -> "admin#{System.unique_integer([:positive])}@example.com" end),
        name: "Admin",
        admin: true
      },
      overrides: opts,
      authorize?: false
    )
  end

  def tax_rate(opts \\ []) do
    changeset_generator(
      TaxRate,
      :create,
      defaults: %{
        name: StreamData.repeatedly(fn -> "Tax Rate #{System.unique_integer([:positive])}" end),
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
        name: "Promotion",
        code: StreamData.repeatedly(fn -> "PROMO-#{System.unique_integer([:positive])}" end),
        discount_rate: "0.20",
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
        name: "Category",
        # slug has a unique index; without this Ash fills it with a random short
        # string that occasionally collides. Must be unique across concurrently
        # running tests (not sequence/2, which restarts per test process) or
        # concurrent sandbox transactions deadlock on the index.
        slug: StreamData.repeatedly(fn -> "category-#{System.unique_integer([:positive])}" end)
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
        name: StreamData.repeatedly(fn -> "Product #{System.unique_integer([:positive])}" end),
        description: "Product description",
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

  def order(opts \\ []) do
    # For testing orders, we use seed_generator to allow setting any attribute
    # including internal ones that wouldn't normally be accepted in actions
    # (like fulfillment_fee, payment_intent_id, promotion_id, etc.)
    # We provide a base struct to avoid generating random foreign keys that don't exist
    seed_generator(
      %Order{
        state: :contact_details,
        order_reference: GenerateOrderReference.generate(),
        vat_breakdown: if(opts[:state] == :placed, do: [], else: nil)
      },
      overrides: opts,
      authorize?: false
    )
  end

  def line_item(opts \\ []) do
    changeset_generator(LineItem, :add_to_cart,
      defaults: %{
        quantity: 1,
        is_card: false
      },
      overrides: opts,
      authorize?: false
    )
  end

  def fulfillment_option(opts \\ []) do
    tax_rate_id = opts[:tax_rate_id] || once(:default_tax_rate_id, fn -> generate(tax_rate()).id end)
    method = opts[:fulfillment_method] || :pickup
    sort_key = opts[:sort_key] || if method == :delivery, do: 0, else: 1

    changeset_generator(FulfillmentOption, :create,
      defaults: %{
        tax_rate_id: tax_rate_id,
        name: StreamData.repeatedly(fn -> "Fulfillment Option #{System.unique_integer([:positive])}" end),
        fulfillment_method: :pickup,
        sort_key: sort_key,
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

  def course(opts \\ []) do
    tax_rate_id = opts[:tax_rate_id] || once(:default_tax_rate_id, fn -> generate(tax_rate()).id end)

    changeset_generator(
      Course,
      :create,
      defaults: %{
        name: sequence(:course_name, &"Course #{&1}"),
        description: "An afternoon with flowers.",
        location_name: "Minimossen",
        location_address: "Myrvägen 1, 65230 Vasa",
        image_slug: "local:///image_1.jpg",
        date: Date.add(Date.utc_today(), 30),
        start_time: ~T[10:00:00],
        end_time: ~T[14:00:00],
        register_before: Date.add(Date.utc_today(), 20),
        total_places: 8,
        price: "85.00",
        tax_rate_id: tax_rate_id
      },
      overrides: opts,
      authorize?: false
    )
  end

  # seed_generator, not the :register action, so a registration can be attached
  # to any user directly: :register always links the user with its email.
  def course_registration(opts \\ []) do
    opts = Keyword.put_new_lazy(opts, :course_id, fn -> generate(course()).id end)

    seed_generator(
      %CourseRegistration{
        name: "Ada Lovelace",
        email: "ada@example.com",
        status: :pending,
        seats: 1,
        locale: "en-GB",
        reference: GenerateOrderReference.generate(),
        tax_rate: Decimal.new("0.255"),
        amount: Decimal.new("85.00")
      },
      overrides: opts,
      authorize?: false
    )
  end

  def with_token(user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
    %{user | __metadata__: Map.put(user.__metadata__ || %{}, :token, token)}
  end
end
