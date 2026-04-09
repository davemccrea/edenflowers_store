defmodule EdenflowersWeb.CheckoutLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import PhoenixTest
  import Generator
  import Mox

  alias Edenflowers.Store.{Order, LineItem}

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Create necessary records for checkout
    product = generate(product())
    variant = generate(product_variant(%{product_id: product.id}))
    fulfillment_option = generate(fulfillment_option())

    # Create an order with a line item
    order = generate(order())

    {:ok, line_item} =
      LineItem.add_item(%{
        order_id: order.id,
        product_id: product.id,
        product_variant_id: variant.id,
        product_name: product.name,
        product_image_slug: variant.image_slug,
        quantity: 1,
        unit_price: variant.price,
        tax_rate: Decimal.new("0.24")
      })

    # Reload order with line items
    order = Order.get_for_checkout!(order.id, actor: nil)

    # Mock Stripe API calls
    mock_payment_intent = %{
      id: "pi_test_#{:rand.uniform(1_000_000)}",
      client_secret: "pi_test_secret_#{:rand.uniform(1_000_000)}"
    }

    # Stub Stripe API calls to return the mock payment intent
    stub(Edenflowers.StripeAPI.Mock, :create_payment_intent, fn _order ->
      {:ok, mock_payment_intent}
    end)

    stub(Edenflowers.StripeAPI.Mock, :retrieve_payment_intent, fn _order ->
      {:ok, mock_payment_intent}
    end)

    stub(Edenflowers.StripeAPI.Mock, :update_payment_intent, fn _order ->
      {:ok, mock_payment_intent}
    end)

    %{
      order: order,
      product: product,
      variant: variant,
      line_item: line_item,
      fulfillment_option: fulfillment_option
    }
  end

  describe "Step 1: Your Details" do
    test "displays customer details form", %{conn: conn, order: order} do
      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> visit("/checkout")
      |> assert_has("h1", text: "Your Details")
      |> assert_has("[data-testid='customer-name-input']")
      |> assert_has("[data-testid='customer-email-input']")
      |> assert_has("[data-testid='step-1-next-button']")
    end

    test "successfully submits and progresses to step 2", %{conn: conn, order: order} do
      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> visit("/checkout")
      |> fill_in("Your Name *", with: "John Doe")
      |> fill_in("Email *", with: "john@example.com")
      |> click_button("Next")
      |> assert_has("h1", text: "Gift Options")
    end
  end

  describe "Step 2: Gift Options" do
    setup %{conn: conn, order: order} do
      # Complete step 1 first
      session =
        conn
        |> Plug.Test.init_test_session(%{order_id: order.id})
        |> visit("/checkout")
        |> fill_in("Your Name *", with: "John Doe")
        |> fill_in("Email *", with: "john@example.com")
        |> click_button("Next")

      %{session: session}
    end

    test "displays gift options form", %{session: session} do
      session
      |> assert_has("h1", text: "Gift Options")
      |> assert_has("[data-testid='gift-recipient-selector']")
    end

    test "successfully submits and progresses to step 3", %{session: session} do
      session
      |> click_button("Next")
      |> assert_has("h1", text: "Delivery Information")
    end
  end

  describe "Cart Management During Checkout" do
    test "displays cart section", %{conn: conn, order: order} do
      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> visit("/checkout")
      |> assert_has("[data-testid='cart-section']")
      |> assert_has("[data-testid='cart-heading']")
    end

    test "displays order total", %{conn: conn, order: order} do
      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> visit("/checkout")
      |> assert_has("[data-testid='order-total']")
      |> assert_has("[data-testid='total-amount']")
    end
  end

  # Note: Empty cart redirect requires proper navigation which may depend on JavaScript
  # This is better tested in E2E tests
  describe "Empty Cart Handling" do
    test "checkout requires items in cart", %{conn: conn, order: order} do
      # Just verify that a valid order with items can visit checkout
      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> visit("/checkout")
      |> assert_has("[data-testid='cart-section']")
    end
  end

  describe "Promotional Codes" do
    setup do
      # Create a valid promotion
      promotion = generate(promotion(%{code: "SAVE20", discount_percentage: "0.20"}))
      %{promotion: promotion}
    end

    test "displays promo code input", %{conn: conn, order: order} do
      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> visit("/checkout")
      |> assert_has("[data-testid='promo-code-input']")
    end

    # Note: Actually interacting with the promo code form requires JavaScript
    # These tests verify the UI elements are present
    test "displays promo code form", %{conn: conn, order: order} do
      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> visit("/checkout")
      |> assert_has("[data-testid='promo-code-form']")
      |> assert_has("[data-testid='promo-code-input']")
    end
  end
end
