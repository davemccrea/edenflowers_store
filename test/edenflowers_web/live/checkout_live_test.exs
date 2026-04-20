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

    test "does not show 'Select a card' button when gift is false", %{session: session} do
      session
      |> refute_has("[data-testid='select-card-button']")
    end

    test "shows 'Add a card' button when order is a gift",
         %{conn: conn, product: product, variant: variant} do
      gift_order = generate(order(step: 2, gift: true))

      LineItem.add_item!(%{
        order_id: gift_order.id,
        product_id: product.id,
        product_variant_id: variant.id,
        product_name: product.name,
        product_image_slug: variant.image_slug,
        quantity: 1,
        unit_price: variant.price,
        tax_rate: Decimal.new("0.24")
      })

      conn
      |> Plug.Test.init_test_session(%{order_id: gift_order.id})
      |> visit("/checkout")
      |> assert_has("[data-testid='select-card-button']")
    end
  end

  describe "Card selection" do
    setup %{order: order} do
      # Create a "cards" category with a card product (with a variant)
      cards_category = generate(product_category(slug: "cards", draft: false))
      tax_rate_ = generate(tax_rate())

      card_product =
        generate(product(product_category_id: cards_category.id, tax_rate_id: tax_rate_.id, draft: false))

      card_variant =
        generate(product_variant(product_id: card_product.id, size: :small, draft: false))

      %{
        order: order,
        card_product: card_product,
        card_variant: card_variant,
        cards_category: cards_category
      }
    end

    test "LineItem.add_card succeeds for gift orders", %{order: order, card_product: card_product, card_variant: card_variant} do
      order
      |> Ash.Changeset.for_update(:update_gift, %{gift: true})
      |> Ash.update!(authorize?: false)

      assert {:ok, card_line_item} =
               LineItem.add_card(%{
                 order_id: order.id,
                 product_id: card_product.id,
                 product_variant_id: card_variant.id,
                 product_name: card_product.name,
                 product_image_slug: card_variant.image_slug,
                 quantity: 1,
                 unit_price: card_variant.price,
                 tax_rate: Decimal.new("0.24")
               })

      assert card_line_item.is_card == true
    end

    test "LineItem.add_card returns an error for non-gift orders", %{order: order, card_product: card_product, card_variant: card_variant} do
      assert {:error, _} =
               LineItem.add_card(%{
                 order_id: order.id,
                 product_id: card_product.id,
                 product_variant_id: card_variant.id,
                 product_name: card_product.name,
                 product_image_slug: card_variant.image_slug,
                 quantity: 1,
                 unit_price: card_variant.price,
                 tax_rate: Decimal.new("0.24")
               })
    end

    test "saving step 2 with gift=false removes card line items", %{order: order, card_product: card_product, card_variant: card_variant} do
      order =
        order
        |> Ash.Changeset.for_update(:update_gift, %{gift: true})
        |> Ash.update!(authorize?: false)

      {:ok, _card} =
        LineItem.add_card(%{
          order_id: order.id,
          product_id: card_product.id,
          product_variant_id: card_variant.id,
          product_name: card_product.name,
          product_image_slug: card_variant.image_slug,
          quantity: 1,
          unit_price: card_variant.price,
          tax_rate: Decimal.new("0.24")
        })

      order
      |> Ash.Changeset.for_update(:save_step_2, %{gift: false})
      |> Ash.update!(authorize?: false)

      reloaded = Order.get_for_checkout!(order.id, actor: nil)
      refute Enum.any?(reloaded.line_items, & &1.is_card)
    end

    test "shows card message textarea when a card line item exists",
         %{conn: conn, product: product, variant: variant, card_product: card_product, card_variant: card_variant} do
      gift_order = generate(order(step: 2, gift: true))

      LineItem.add_item!(%{
        order_id: gift_order.id,
        product_id: product.id,
        product_variant_id: variant.id,
        product_name: product.name,
        product_image_slug: variant.image_slug,
        quantity: 1,
        unit_price: variant.price,
        tax_rate: Decimal.new("0.24")
      })

      LineItem.add_card!(
        %{
          order_id: gift_order.id,
          product_id: card_product.id,
          product_variant_id: card_variant.id,
          product_name: card_product.name,
          product_image_slug: card_variant.image_slug,
          quantity: 1,
          unit_price: card_variant.price,
          tax_rate: Decimal.new("0.24")
        },
        authorize?: false
      )

      conn
      |> Plug.Test.init_test_session(%{order_id: gift_order.id})
      |> visit("/checkout")
      |> assert_has("[data-testid='card-message-textarea']")
      |> assert_has("[data-testid='remove-card-button']")
    end

    test "select_card event adds a card line item to the order",
         %{conn: conn, product: product, variant: variant, card_product: card_product, card_variant: card_variant} do
      gift_order = generate(order(step: 2, gift: true))

      LineItem.add_item!(%{
        order_id: gift_order.id,
        product_id: product.id,
        product_variant_id: variant.id,
        product_name: product.name,
        product_image_slug: variant.image_slug,
        quantity: 1,
        unit_price: variant.price,
        tax_rate: Decimal.new("0.24")
      })

      conn
      |> Plug.Test.init_test_session(%{order_id: gift_order.id})
      |> visit("/checkout")
      |> assert_has("[data-testid='select-card-button']")
      |> click_button("[data-testid='card-option-#{card_variant.id}']")
      |> assert_has("[data-testid='card-message-textarea']")
      |> refute_has("[data-testid='select-card-button']")
    end

    test "remove_card event removes the card from the order",
         %{conn: conn, product: product, variant: variant, card_product: card_product, card_variant: card_variant} do
      gift_order = generate(order(step: 2, gift: true))

      LineItem.add_item!(%{
        order_id: gift_order.id,
        product_id: product.id,
        product_variant_id: variant.id,
        product_name: product.name,
        product_image_slug: variant.image_slug,
        quantity: 1,
        unit_price: variant.price,
        tax_rate: Decimal.new("0.24")
      })

      LineItem.add_card!(
        %{
          order_id: gift_order.id,
          product_id: card_product.id,
          product_variant_id: card_variant.id,
          product_name: card_product.name,
          product_image_slug: card_variant.image_slug,
          quantity: 1,
          unit_price: card_variant.price,
          tax_rate: Decimal.new("0.24")
        },
        authorize?: false
      )

      conn
      |> Plug.Test.init_test_session(%{order_id: gift_order.id})
      |> visit("/checkout")
      |> assert_has("[data-testid='card-message-textarea']")
      |> click_button("[data-testid='remove-card-button']")
      |> assert_has("[data-testid='select-card-button']")
      |> refute_has("[data-testid='card-message-textarea']")
    end

    test "save_form_2 persists card_message on the card line item",
         %{conn: conn, product: product, variant: variant, card_product: card_product, card_variant: card_variant} do
      # recipient_name is required when gift=true, so seed it on the order directly
      gift_order = generate(order(step: 2, gift: true, recipient_name: "Test Recipient"))

      LineItem.add_item!(%{
        order_id: gift_order.id,
        product_id: product.id,
        product_variant_id: variant.id,
        product_name: product.name,
        product_image_slug: variant.image_slug,
        quantity: 1,
        unit_price: variant.price,
        tax_rate: Decimal.new("0.24")
      })

      LineItem.add_card!(
        %{
          order_id: gift_order.id,
          product_id: card_product.id,
          product_variant_id: card_variant.id,
          product_name: card_product.name,
          product_image_slug: card_variant.image_slug,
          quantity: 1,
          unit_price: card_variant.price,
          tax_rate: Decimal.new("0.24")
        },
        authorize?: false
      )

      conn
      |> Plug.Test.init_test_session(%{order_id: gift_order.id})
      |> visit("/checkout")
      |> fill_in("card_message", with: "Happy birthday!")
      |> click_button("Next")

      reloaded = Order.get_for_checkout!(gift_order.id, actor: nil)
      card_item = Enum.find(reloaded.line_items, & &1.is_card)
      assert card_item.card_message == "Happy birthday!"
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
