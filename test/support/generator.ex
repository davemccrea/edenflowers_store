defmodule Generator do
  use Ash.Generator

  alias Edenflowers.Accounts.User

  alias Edenflowers.Pricing.{TaxRate, Promotion}
  alias Edenflowers.Catalog.{ProductCategory, Product, ProductVariant}
  alias Edenflowers.Orders.{Order, LineItem, Subscription}
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
        image_slug: "image.png",
        free_delivery: false,
        subscribable: false
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
    # seed_generator so tests can set attributes no action accepts. The base
    # struct avoids random foreign keys that don't exist.
    {payment_status, opts} = Keyword.pop(opts, :payment_status)

    opts =
      case payment_status do
        nil ->
          opts

        :pending ->
          opts

        status ->
          raise ArgumentError, "seed payments instead of setting calculated payment_status to #{inspect(status)}"
      end

    seed_generator(
      %Order{
        state: :contact_details,
        order_reference: StreamData.repeatedly(fn -> "T#{System.unique_integer([:positive])}" end),
        vat_breakdown: if(opts[:state] == :placed, do: [], else: nil)
      },
      overrides: opts,
      authorize?: false
    )
  end

  @doc "Records money received for an order, as a Stripe payment unless `method:` says otherwise."
  def payment(opts \\ []) do
    seed_generator(
      %Edenflowers.Orders.Payment{amount: Decimal.new("10.00"), method: :stripe},
      overrides: opts,
      authorize?: false
    )
  end

  @doc """
  A placed order from Ada Lovelace for two items at 42.00, picked up for 4.50:
  88.50 in all, and nothing paid yet.

  `paid: true` pays the grand total when the order was placed, and
  `paid: "40.00"` pays that amount instead. `refunded: true` pays it and then
  returns it. Any other option overrides the order's attributes.
  """
  def placed_order(opts \\ []) do
    {refunded?, opts} = Keyword.pop(opts, :refunded, false)
    {paid, opts} = Keyword.pop(opts, :paid, refunded?)

    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    variant = generate(product_variant(product_id: product.id, price: "42.00"))
    fulfillment_option = generate(fulfillment_option(tax_rate_id: tax_rate.id))

    attrs =
      Keyword.merge(
        [
          state: :placed,
          customer_name: "Ada Lovelace",
          customer_email: "ada@example.com",
          fulfillment_option_id: fulfillment_option.id,
          fulfillment_option_name: "Pickup",
          fulfillment_method: :pickup,
          fulfillment_date: ~D[2026-06-10],
          quoted_fulfillment_fee: "4.50",
          fulfillment_tax_rate: tax_rate.percentage,
          payment_intent_id: "pi_test_#{System.unique_integer([:positive])}",
          ordered_at: DateTime.utc_now(),
          locale: "en-GB"
        ],
        opts
      )

    order = generate(order(attrs))
    generate(line_item(order_id: order.id, product_variant_id: variant.id, quantity: 2))
    order = Ash.load!(order, :grand_total, authorize?: false)

    amount_paid =
      case paid do
        true -> order.grand_total
        false -> nil
        amount -> Decimal.new(amount)
      end

    paid_at = order.ordered_at || DateTime.utc_now()

    if amount_paid,
      do: generate(payment(order_id: order.id, amount: amount_paid, paid_at: paid_at))

    if amount_paid && refunded?,
      do: generate(payment(order_id: order.id, amount: Decimal.negate(amount_paid), paid_at: paid_at))

    Ash.load!(order, :payment_status, authorize?: false, reuse_values?: false)
  end

  @doc """
  John Smith's order waiting on its Stripe PaymentIntent: one item and a
  fulfillment fee, loaded with its grand total.

  `product_variant_id:` picks the item; any other option overrides the
  order's attributes.
  """
  def order_in_payment(opts \\ []) do
    tax_rate = generate(tax_rate())

    {product_variant_id, opts} =
      Keyword.pop_lazy(opts, :product_variant_id, fn ->
        generate(product_variant(product_id: generate(product(tax_rate_id: tax_rate.id)).id)).id
      end)

    fulfillment_option = generate(fulfillment_option(tax_rate_id: tax_rate.id))
    %{fulfillment_fee: fulfillment_fee} = Edenflowers.Fulfillment.Fee.calculate(fulfillment_option, 0)

    {:ok, user} = Edenflowers.Accounts.upsert_user("john.smith@example.com", "John Smith", authorize?: false)

    attrs =
      Keyword.merge(
        [
          state: :payment,
          customer_name: "John Smith",
          customer_email: "john.smith@example.com",
          user_id: user.id,
          fulfillment_option_id: fulfillment_option.id,
          fulfillment_date: Date.utc_today(),
          quoted_fulfillment_fee: fulfillment_fee,
          payment_intent_id: "pi_test_#{System.unique_integer([:positive])}"
        ],
        opts
      )

    order = generate(order(attrs))
    generate(line_item(order_id: order.id, product_variant_id: product_variant_id, quantity: 1))
    Ash.load!(order, :grand_total, authorize?: false)
  end

  # seed_generator because a Subscription is only ever created by checkout.
  def subscription(opts \\ []) do
    opts =
      opts
      |> Keyword.put_new_lazy(:user_id, fn -> generate(admin_user(admin: false)).id end)
      |> Keyword.put_new_lazy(:product_variant_id, fn ->
        generate(product_variant(product_id: generate(product()).id)).id
      end)
      |> Keyword.put_new_lazy(:fulfillment_option_id, fn ->
        generate(fulfillment_option(fulfillment_method: :delivery)).id
      end)

    seed_generator(
      %Subscription{
        interval_weeks: 2,
        next_fulfillment_date: Date.add(Edenflowers.Expressions.HelsinkiToday.today(), 14),
        locale: "en",
        stripe_customer_id: "cus_ada",
        stripe_payment_method_id: "pm_card"
      },
      overrides: opts,
      authorize?: false
    )
  end

  @doc "Counts towards a promotion's usage by placing `times` orders with it."
  def use_promotion(promotion, times \\ 1) do
    for _ <- 1..times do
      generate(order(state: :placed, promotion_id: promotion.id))
    end
  end

  def line_item(opts \\ []) do
    changeset_generator(LineItem, :add_to_cart,
      defaults: %{
        quantity: 1,
        is_card: false,
        interval_weeks: nil
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
        reference: StreamData.repeatedly(fn -> "T#{System.unique_integer([:positive])}" end),
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
