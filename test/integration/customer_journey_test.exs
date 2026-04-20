defmodule Edenflowers.Integration.CustomerJourneyTest do
  use EdenflowersWeb.ConnCase
  import PhoenixTest
  import Generator
  import Mox

  setup :verify_on_exit!

  # Shared setup: one product with three variants, one pickup option, one delivery option.
  # Stripe API is stubbed throughout. Here API is stubbed for delivery scenarios.
  setup do
    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    _small = generate(product_variant(product_id: product.id, size: :small, price: "25.00"))
    _medium = generate(product_variant(product_id: product.id, size: :medium, price: "35.00"))
    _large = generate(product_variant(product_id: product.id, size: :large, price: "45.00"))

    pickup = generate(fulfillment_option(tax_rate_id: tax_rate.id, fulfillment_method: :pickup, rate_type: :fixed, base_price: "5.00", same_day: true, order_deadline: ~T[15:00:00]))
    delivery = generate(fulfillment_option(tax_rate_id: tax_rate.id, fulfillment_method: :delivery, rate_type: :dynamic, base_price: "4.50", price_per_km: "1.60", free_dist_km: 5, max_dist_km: 20, same_day: false, order_deadline: ~T[12:00:00]))

    order = generate(order())

    mock_pi = %{id: "pi_test_123", client_secret: "pi_test_secret_123"}
    stub(Edenflowers.StripeAPI.Mock, :create_payment_intent, fn _ -> {:ok, mock_pi} end)
    stub(Edenflowers.StripeAPI.Mock, :retrieve_payment_intent, fn _ -> {:ok, mock_pi} end)
    stub(Edenflowers.StripeAPI.Mock, :update_payment_intent, fn _ -> {:ok, mock_pi} end)

    %{product: product, pickup: pickup, delivery: delivery, order: order}
  end

  # ---------------------------------------------------------------------------
  # Core checkout flows
  # ---------------------------------------------------------------------------

  describe "Pickup checkout (happy path)" do
    # Covers: product page → add to cart → step 1 (details) → step 2 (gift) →
    # step 3 (pickup + date) → step 4 (payment) → order confirmed.
    @tag :skip
    test "guest completes full pickup checkout", %{conn: conn, product: _product, order: _order} do
    end
  end

  describe "Delivery checkout (happy path)" do
    # Covers: same flow as pickup but with delivery address.
    # Requires stubbing Here API (address lookup + distance calculation).
    @tag :skip
    test "guest completes full delivery checkout", %{conn: conn, product: _product, order: _order} do
    end

    # Verifies the UI surfaces an appropriate error when the address is out of range.
    @tag :skip
    test "shows error when delivery address is outside range", %{conn: conn, product: _product, order: _order} do
    end
  end

  # ---------------------------------------------------------------------------
  # Promotional codes
  # ---------------------------------------------------------------------------

  describe "Promo codes during checkout" do
    # Applies a valid code at checkout and verifies the discounted total is shown.
    @tag :skip
    test "valid promo code reduces order total", %{conn: conn, order: _order} do
    end

    # Submits an invalid/expired code and verifies the error message is displayed.
    @tag :skip
    test "invalid promo code shows error", %{conn: conn, order: _order} do
    end
  end

  # ---------------------------------------------------------------------------
  # Gift flow
  # ---------------------------------------------------------------------------

  describe "Gift checkout" do
    # Sets gift = true, fills in recipient name and message, completes checkout.
    @tag :skip
    test "gift order captures recipient details", %{conn: conn, order: _order} do
    end
  end

  # ---------------------------------------------------------------------------
  # Payment failure
  # ---------------------------------------------------------------------------

  describe "Payment failure" do
    # Stripe webhook delivers payment_intent.payment_failed; order must remain
    # in checkout state and not be finalised.
    @tag :skip
    test "failed payment does not finalise the order" do
    end
  end

  # ---------------------------------------------------------------------------
  # Authentication
  # ---------------------------------------------------------------------------

  describe "Magic link auth" do
    # Submitting a valid email triggers a magic link email.
    @tag :skip
    test "requesting a magic link sends an email" do
    end

    # Following the magic link token signs the user in and redirects them.
    @tag :skip
    test "completing magic link signs the user in" do
    end

    # A used or expired token returns an appropriate error.
    @tag :skip
    test "expired magic link token is rejected" do
    end
  end

  # ---------------------------------------------------------------------------
  # Cart management (via the product page)
  # ---------------------------------------------------------------------------

  describe "Cart management" do
    # Selects a variant on the product page and verifies it appears in the cart.
    @tag :skip
    test "adding a product from the product page appears in checkout cart", %{conn: conn, product: _product, order: _order} do
    end

    # Increments quantity and confirms the cart item count and total update.
    @tag :skip
    test "changing item quantity updates the cart total", %{conn: conn, order: _order} do
    end
  end
end
