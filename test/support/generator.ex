defmodule Generator do
  @moduledoc """
  Ash generators that build the records tests need.
  """

  use Ash.Generator

  alias Edenflowers.Accounts.User

  alias Edenflowers.Catalog.Product
  alias Edenflowers.Catalog.ProductCategory
  alias Edenflowers.Catalog.ProductVariant
  alias Edenflowers.Courses.Course
  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Fulfillment.FulfillmentOption
  alias Edenflowers.Orders.LineItem
  alias Edenflowers.Orders.Order
  alias Edenflowers.Orders.Subscription
  alias Edenflowers.Payments.GiftVoucher
  alias Edenflowers.Pricing.Promotion
  alias Edenflowers.Pricing.TaxRate

  # seed_generator bypasses actions so tests can set :admin directly
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
        # Slugs must be unique across concurrent tests to avoid collisions and
        # deadlocks on the unique index. sequence/2 restarts in each test process,
        # so use a VM-wide unique integer instead of it or a random short string.
        slug: StreamData.repeatedly(fn -> "category-#{System.unique_integer([:positive])}" end),
        add_on: false,
        # Keep the category type deterministic because only wreaths retain bow colours.
        product_type: :flowers
      },
      overrides: opts,
      authorize?: false
    )
  end

  def product(opts \\ []) do
    tax_rate_id = opts[:tax_rate_id] || once(:default_tax_rate_id, fn -> generate(tax_rate()).id end)

    # Only a wreath category keeps a product's bow colours.
    product_category_id =
      cond do
        opts[:product_category_id] ->
          opts[:product_category_id]

        opts[:bow_colours] not in [nil, []] ->
          once(:bow_category_id, fn -> generate(product_category(product_type: :wreath)).id end)

        true ->
          once(:default_product_category_id, fn -> generate(product_category()).id end)
      end

    changeset_generator(Product, :create,
      defaults: %{
        product_category_id: product_category_id,
        tax_rate_id: tax_rate_id,
        name: StreamData.repeatedly(fn -> "Product #{System.unique_integer([:positive])}" end),
        description: "Product description",
        # Left to StreamData, a random translation would replace the name in an order's language.
        translations: %{},
        # Left to StreamData, a random slug would replace the one made from the name.
        slug: nil,
        photo_slugs: ["image.png"],
        free_delivery: false,
        subscribable: false,
        bow_colours: []
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
        stock_quantity: nil
      },
      overrides: opts,
      authorize?: false
    )
  end

  def order(opts \\ []) do
    # Use seed_generator so tests can set attributes no action accepts. Starting
    # from a struct avoids generating random foreign keys for nonexistent records.
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

    opts = snapshot_promotion(opts)

    seed_generator(
      %Order{
        state: :contact_details,
        order_reference: StreamData.repeatedly(fn -> "T#{System.unique_integer([:positive])}" end),
        vat_breakdown: if(opts[:state] == :placed, do: [], else: nil),
        stored_grand_total: if(opts[:state] == :placed, do: 0, else: nil)
      },
      overrides: opts,
      authorize?: false,
      after_action: &store_live_grand_total/1
    )
  end

  # An order takes its promotion's discount rate with it, as ApplyPromotion does.
  defp snapshot_promotion(opts) do
    case opts[:promotion_id] do
      nil ->
        opts

      promotion_id ->
        Keyword.put_new_lazy(opts, :discount_rate, fn ->
          Ash.get!(Edenflowers.Pricing.Promotion, promotion_id, authorize?: false).discount_rate
        end)
    end
  end

  @doc "Places a seeded cart directly, storing its grand total as placing it would."
  def seed_placed(order, attrs \\ %{}) do
    order = Ash.load!(order, :grand_total, authorize?: false, reuse_values?: false)
    Ash.Seed.update!(order, Map.merge(%{state: :placed, stored_grand_total: order.grand_total}, attrs))
  end

  # Seeding skips Changes.SnapshotVatBreakdown, so placed orders store the
  # live total here, again each time a line is added.
  defp store_live_grand_total(%Order{state: :placed} = order) do
    order = Ash.load!(order, :grand_total, authorize?: false, reuse_values?: false)

    # Left alone when it already matches, so an updated_at a test set stays put.
    if Decimal.eq?(order.stored_grand_total, order.grand_total),
      do: order,
      else: Ash.Seed.update!(order, %{stored_grand_total: order.grand_total})
  end

  defp store_live_grand_total(order), do: order

  @doc "Records money received for an order or course booking, as a Stripe payment unless `method:` says otherwise."
  def payment(opts \\ []) do
    seed_generator(
      %Edenflowers.Payments.Payment{amount: Decimal.new("10.00"), method: :stripe},
      overrides: opts,
      authorize?: false
    )
  end

  @doc """
  Creates Ada Lovelace's placed pickup order with two items at 42.00 each and a
  4.50 pickup fee. The default total is 88.50, with no payment recorded.

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
  Creates John Smith's order in the payment step with a Stripe PaymentIntent ID,
  one item and a fulfillment fee. Loads the grand total and Stripe amount.

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
          fulfillment_date: Edenflowers.ShopTime.today(),
          quoted_fulfillment_fee: fulfillment_fee,
          payment_intent_id: "pi_test_#{System.unique_integer([:positive])}"
        ],
        opts
      )

    order = generate(order(attrs))
    generate(line_item(order_id: order.id, product_variant_id: product_variant_id, quantity: 1))
    Ash.load!(order, [:grand_total, :stripe_amount], authorize?: false)
  end

  # Seed subscriptions directly so tests do not need to complete checkout to create one.
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
      |> Keyword.put_new(:next_fulfillment_date, Date.add(Edenflowers.ShopTime.today(), 14))

    opts = Keyword.put_new(opts, :delivery_day, Edenflowers.Fulfillment.Weekday.from_date(opts[:next_fulfillment_date]))

    seed_generator(
      %Subscription{
        interval_weeks: 2,
        locale: "en",
        stripe_customer_id: "cus_ada",
        stripe_payment_method_id: "pm_card"
      },
      overrides: opts,
      authorize?: false
    )
  end

  @doc """
  Builds a generator for a 50.00 gift voucher with the default one-year expiry.
  Unless `line_item_id` is supplied, creates a line item on a separate placed
  order to represent the sale. The generated code is available in `code`.
  """
  def gift_voucher(opts \\ []) do
    opts =
      Keyword.put_new_lazy(opts, :line_item_id, fn ->
        order = generate(order(state: :placed))
        variant = generate(product_variant(product_id: generate(product()).id))
        generate(line_item(order_id: order.id, product_variant_id: variant.id)).id
      end)

    seed_generator(
      %GiftVoucher{
        code: StreamData.repeatedly(&GiftVoucher.generate_code/0),
        amount: Decimal.new("50.00"),
        expires_on: GiftVoucher.default_expiry()
      },
      overrides: opts,
      authorize?: false
    )
  end

  @doc "Seeds `times` placed orders with the promotion so they count towards its usage."
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
        interval_weeks: nil,
        bow_colour: nil
      },
      overrides: opts,
      authorize?: false,
      after_action: fn line_item ->
        line_item |> Ash.load!(:order, authorize?: false) |> Map.fetch!(:order) |> store_live_grand_total()
        line_item
      end
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
        max_dist_km: 20
      },
      overrides: opts,
      authorize?: false
    )
  end

  @doc """
  Updates the shared shop calendar. Its default state allows every weekday but
  disables same-day fulfillment.

  The update locks the one row until the test's transaction rolls back, so
  modules that write the calendar run `async: false`. Tests of pure calendar
  logic build a `%ShopCalendar{}` instead.
  """
  def shop_calendar(attrs \\ []) do
    Edenflowers.Fulfillment.get_shop_calendar!(authorize?: false)
    |> Ash.Seed.update!(Map.new(attrs))
  end

  def course(opts \\ []) do
    tax_rate_id = opts[:tax_rate_id] || once(:default_tax_rate_id, fn -> generate(tax_rate()).id end)

    changeset_generator(
      Course,
      :create,
      defaults: %{
        name: sequence(:course_name, &"Course #{&1}"),
        draft: false,
        # Left to StreamData, a random slug would replace the one made from the name.
        slug: nil,
        description: "An afternoon with flowers.",
        location_name: "Minimossen",
        location_address: "Myrvägen 1, 65230 Vasa",
        image_slug: "local:///image_1.jpg",
        photo_credit_name: nil,
        photo_credit_url: nil,
        date: Date.add(Edenflowers.ShopTime.today(), 30),
        start_time: ~T[10:00:00],
        end_time: ~T[14:00:00],
        register_before: Date.add(Edenflowers.ShopTime.today(), 20),
        total_places: 8,
        price: "85.00",
        cancellation_days: 7,
        cancellation_fee_percent: 0,
        tax_rate_id: tax_rate_id
      },
      overrides: opts,
      authorize?: false
    )
  end

  # Seed registrations so tests can attach any user directly. The :register
  # action instead chooses the user by the registration's email address.
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
