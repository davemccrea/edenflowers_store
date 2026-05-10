defmodule EdenflowersWeb.CheckoutLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import PhoenixTest

  import Phoenix.LiveViewTest,
    only: [
      live: 2,
      render_click: 3,
      element: 2,
      render_blur: 2,
      render_submit: 2,
      render_async: 1,
      assert_redirect: 2
    ]

  import Generator
  import Mox
  import ExUnit.CaptureLog

  alias Edenflowers.Store.{Cart, CartLineItem}

  setup :verify_on_exit!

  setup do
    product = generate(product())
    variant = generate(product_variant(%{product_id: product.id}))
    generate(fulfillment_option())

    order = generate(cart())

    {:ok, _line_item} =
      CartLineItem.add_item(%{
        cart_id: order.id,
        product_variant_id: variant.id,
        quantity: 1
      })

    order = Cart.get_for_checkout!(order.id, actor: nil)

    mock_payment_intent = %{
      id: "pi_test_#{:rand.uniform(1_000_000)}",
      client_secret: "pi_test_secret_#{:rand.uniform(1_000_000)}"
    }

    stub(Edenflowers.StripeAPI.Mock, :create_payment_intent, fn _order ->
      {:ok, mock_payment_intent}
    end)

    stub(Edenflowers.StripeAPI.Mock, :retrieve_payment_intent, fn _order ->
      {:ok, mock_payment_intent}
    end)

    stub(Edenflowers.StripeAPI.Mock, :update_payment_intent, fn _order ->
      {:ok, mock_payment_intent}
    end)

    %{order: order, product: product, variant: variant}
  end

  describe "Step 1: Your Details" do
    test "successfully submits and progresses to step 2", %{conn: conn, order: order} do
      conn
      |> Plug.Test.init_test_session(%{cart_id: order.id})
      |> visit("/checkout")
      |> fill_in("Your Name *", with: "John Doe")
      |> fill_in("Email *", with: "john@example.com")
      |> click_button("Next")
      |> assert_has("h2", text: "Gift Options")
    end
  end

  describe "Step 2: Gift Options" do
    setup %{conn: conn, order: order} do
      session =
        conn
        |> Plug.Test.init_test_session(%{cart_id: order.id})
        |> visit("/checkout")
        |> fill_in("Your Name *", with: "John Doe")
        |> fill_in("Email *", with: "john@example.com")
        |> click_button("Next")

      %{session: session}
    end

    test "successfully submits and progresses to step 3", %{session: session} do
      session
      |> click_button("Next")
      |> assert_has("h2", text: "Delivery Information")
    end

    test "does not show 'Select a card' button when gift is false", %{session: session} do
      session
      |> refute_has("[data-testid='select-card-button']")
    end

    test "shows 'Add a card' button when order is a gift",
         %{conn: conn, variant: variant} do
      gift_order = generate(cart(state: :gift_options, gift: true))

      CartLineItem.add_item!(%{
        cart_id: gift_order.id,
        product_variant_id: variant.id,
        quantity: 1
      })

      conn
      |> Plug.Test.init_test_session(%{cart_id: gift_order.id})
      |> visit("/checkout")
      |> assert_has("[data-testid='select-card-button']")
    end
  end

  describe "Step 3: Delivery Information" do
    setup %{conn: conn, variant: variant} do
      # The shared setup already created one pickup option (insertion order: pickup
      # first). Add a delivery option afterwards so we can verify that delivery
      # still wins the default and renders first regardless of insertion order.
      delivery_option =
        generate(
          fulfillment_option(
            fulfillment_method: :delivery,
            rate_type: :fixed,
            base_price: "5.00",
            name: "Home delivery"
          )
        )

      step_3_order = generate(cart(state: :delivery, customer_name: "Jane", customer_email: "jane@example.com"))

      CartLineItem.add_item!(%{
        cart_id: step_3_order.id,
        product_variant_id: variant.id,
        quantity: 1
      })

      conn = Plug.Test.init_test_session(conn, %{cart_id: step_3_order.id})

      %{conn: conn, step_3_order: step_3_order, delivery_option: delivery_option}
    end

    test "fresh order at step 3 defaults the radio to home delivery", %{
      conn: conn,
      step_3_order: step_3_order,
      delivery_option: delivery_option
    } do
      {:ok, _view, html} = live(conn, ~p"/checkout")

      pickup_option =
        Edenflowers.Store.FulfillmentOption.list!()
        |> Enum.find(&(&1.fulfillment_method == :pickup))

      assert html =~ ~s(value="#{delivery_option.id}" checked)
      refute html =~ ~s(value="#{pickup_option.id}" checked)

      reloaded = Cart.get_for_checkout!(step_3_order.id, actor: nil)
      assert reloaded.fulfillment_option_id == delivery_option.id
      assert reloaded.fulfillment_method == :delivery
    end

    test "existing pickup choice is preserved on revisit", %{
      conn: conn,
      step_3_order: step_3_order,
      delivery_option: delivery_option
    } do
      pickup_option =
        Edenflowers.Store.FulfillmentOption.list!()
        |> Enum.find(&(&1.fulfillment_method == :pickup))

      Cart.update_fulfillment_option!(step_3_order, pickup_option.id, actor: nil)

      {:ok, _view, html} = live(conn, ~p"/checkout")

      assert html =~ ~s(value="#{pickup_option.id}" checked)
      refute html =~ ~s(value="#{delivery_option.id}" checked)

      reloaded = Cart.get_for_checkout!(step_3_order.id, actor: nil)
      assert reloaded.fulfillment_option_id == pickup_option.id
    end

    test "submitting step 3 without changing the radio persists the delivery option", %{
      conn: conn,
      step_3_order: step_3_order,
      delivery_option: delivery_option
    } do
      stub(Edenflowers.HereAPI.Mock, :get_address, fn _query ->
        {:ok, {"Stadsgatan 3, 65300 Vasa", "63.0951,21.6165", "here-id-123"}}
      end)

      stub(Edenflowers.HereAPI.Mock, :get_distance, fn _position -> {:ok, 3000} end)

      {:ok, view, _html} = live(conn, ~p"/checkout")

      view
      |> element("#address-input-field")
      |> render_blur(%{"value" => "Stadsgatan 3, 65300 Vasa"})

      render_async(view)

      view
      |> element("#checkout-form-3b")
      |> render_submit(%{
        "form" => %{
          "delivery_address" => "Stadsgatan 3, 65300 Vasa",
          "recipient_phone_number" => "045 1234567",
          "fulfillment_date" => Date.utc_today() |> Date.add(7) |> Date.to_string()
        }
      })

      reloaded = Cart.get_for_checkout!(step_3_order.id, actor: nil)
      assert reloaded.fulfillment_option_id == delivery_option.id
      assert reloaded.fulfillment_method == :delivery
      assert reloaded.state == :payment
    end

    test "delivery option renders before pickup regardless of insertion order", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/checkout")

      options = Edenflowers.Store.FulfillmentOption.list!()
      delivery_id = Enum.find(options, &(&1.fulfillment_method == :delivery)).id
      pickup_id = Enum.find(options, &(&1.fulfillment_method == :pickup)).id

      {delivery_pos, _} = :binary.match(html, delivery_id)
      {pickup_pos, _} = :binary.match(html, pickup_id)

      assert delivery_pos < pickup_pos
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

    test "saving step 2 with gift=false removes card line items", %{
      card_variant: card_variant
    } do
      order = generate(cart(state: :gift_options, gift: true))
      Cart.add_card!(order, card_variant.id, authorize?: false)

      order
      |> Ash.Changeset.for_update(:submit_gift_options, %{gift: false})
      |> Ash.update!(authorize?: false)

      reloaded = Cart.get_for_checkout!(order.id, actor: nil)
      refute Enum.any?(reloaded.line_items, & &1.is_card)
    end

    test "shows card message textarea when a card line item exists",
         %{conn: conn, variant: variant, card_variant: card_variant} do
      gift_order = generate(cart(state: :gift_options, gift: true))

      CartLineItem.add_item!(%{
        cart_id: gift_order.id,
        product_variant_id: variant.id,
        quantity: 1
      })

      Cart.add_card!(gift_order, card_variant.id, authorize?: false)

      conn
      |> Plug.Test.init_test_session(%{cart_id: gift_order.id})
      |> visit("/checkout")
      |> assert_has("[data-testid='card-message-textarea']")
      |> assert_has("[data-testid='remove-card-button']")
    end

    test "card row in cart sidebar is read-only (no quantity or remove controls)",
         %{conn: conn, variant: variant, card_product: card_product, card_variant: card_variant} do
      gift_order = generate(cart(state: :gift_options, gift: true))

      CartLineItem.add_item!(%{
        cart_id: gift_order.id,
        product_variant_id: variant.id,
        quantity: 1
      })

      card =
        Cart.add_card!(gift_order, card_variant.id, authorize?: false).line_items
        |> Enum.find(& &1.is_card)

      conn
      |> Plug.Test.init_test_session(%{cart_id: gift_order.id})
      |> visit("/checkout")
      # The card line item is still rendered in the cart so the customer can
      # see it on the totals breakdown.
      |> assert_has("#checkout-line-items", text: card_product.name)
      # But its row does not expose +/- or trash controls — those would let
      # the customer accidentally end up with quantity > 1 cards or remove
      # the card from a place that contradicts the dedicated step-2 UI.
      |> refute_has("#checkout-line-items-increment-#{card.id}")
      |> refute_has("#checkout-line-items-decrement-#{card.id}")
      |> refute_has("#checkout-line-items-remove-#{card.id}")
    end

    test "select_card event adds a card line item to the order",
         %{conn: conn, variant: variant, card_product: card_product, card_variant: card_variant} do
      gift_order = generate(cart(state: :gift_options, gift: true))

      CartLineItem.add_item!(%{
        cart_id: gift_order.id,
        product_variant_id: variant.id,
        quantity: 1
      })

      conn
      |> Plug.Test.init_test_session(%{cart_id: gift_order.id})
      |> visit("/checkout")
      |> assert_has("[data-testid='select-card-button']")
      |> click_button("[data-testid='card-option-#{card_variant.id}']", card_product.name)
      |> assert_has("[data-testid='card-message-textarea']")
      |> refute_has("[data-testid='select-card-button']")
    end

    test "remove_card event removes the card from the order",
         %{conn: conn, variant: variant, card_variant: card_variant} do
      gift_order = generate(cart(state: :gift_options, gift: true))

      CartLineItem.add_item!(%{
        cart_id: gift_order.id,
        product_variant_id: variant.id,
        quantity: 1
      })

      Cart.add_card!(gift_order, card_variant.id, authorize?: false)

      conn
      |> Plug.Test.init_test_session(%{cart_id: gift_order.id})
      |> visit("/checkout")
      |> assert_has("[data-testid='card-message-textarea']")
      |> click_button("[data-testid='remove-card-button']", "Remove card")
      |> assert_has("[data-testid='select-card-button']")
      |> refute_has("[data-testid='card-message-textarea']")
    end

    test "save_form_2 persists card_message on the order",
         %{conn: conn, variant: variant, card_variant: card_variant} do
      # recipient_name is required when gift=true, so seed it on the order directly
      gift_order = generate(cart(state: :gift_options, gift: true, recipient_name: "Test Recipient"))

      CartLineItem.add_item!(%{
        cart_id: gift_order.id,
        product_variant_id: variant.id,
        quantity: 1
      })

      Cart.add_card!(gift_order, card_variant.id, authorize?: false)

      conn
      |> Plug.Test.init_test_session(%{cart_id: gift_order.id})
      |> visit("/checkout")
      |> fill_in("Card Message", with: "Happy birthday!")
      |> click_button("Next")

      reloaded = Cart.get_for_checkout!(gift_order.id, actor: nil)
      assert reloaded.card_message == "Happy birthday!"
    end

    test "card_message is preserved across re-renders while on step 2",
         %{conn: conn, variant: variant, card_variant: card_variant} do
      gift_order = generate(cart(state: :gift_options, gift: true, recipient_name: "Original"))

      CartLineItem.add_item!(%{
        cart_id: gift_order.id,
        product_variant_id: variant.id,
        quantity: 1
      })

      Cart.add_card!(gift_order, card_variant.id, authorize?: false)

      conn
      |> Plug.Test.init_test_session(%{cart_id: gift_order.id})
      |> visit("/checkout")
      |> fill_in("Card Message", with: "Happy birthday!")
      |> fill_in("Recipient Name *", with: "Updated Recipient")
      |> assert_has("[data-testid='card-message-textarea']", text: "Happy birthday!")
    end

    test "renders maxlength matching the selected card's size limit",
         %{conn: conn, variant: variant, card_variant: card_variant} do
      gift_order = generate(cart(state: :gift_options, gift: true, recipient_name: "Test"))

      CartLineItem.add_item!(%{
        cart_id: gift_order.id,
        product_variant_id: variant.id,
        quantity: 1
      })

      Cart.add_card!(gift_order, card_variant.id, authorize?: false)

      {:ok, _view, html} =
        conn
        |> Plug.Test.init_test_session(%{cart_id: gift_order.id})
        |> live("/checkout")

      assert html =~ ~s(maxlength="80")
    end

    test "switching from small to large card updates the rendered limit",
         %{conn: conn, variant: variant, card_product: card_product, card_variant: card_variant} do
      large_variant =
        generate(product_variant(product_id: card_product.id, size: :large, draft: false))

      gift_order = generate(cart(state: :gift_options, gift: true, recipient_name: "Test"))

      CartLineItem.add_item!(%{
        cart_id: gift_order.id,
        product_variant_id: variant.id,
        quantity: 1
      })

      Cart.add_card!(gift_order, card_variant.id, authorize?: false)

      {:ok, view, html} =
        conn
        |> Plug.Test.init_test_session(%{cart_id: gift_order.id})
        |> live("/checkout")

      assert html =~ ~s(maxlength="80")

      html = render_click(view, "select_card", %{"variant-id" => large_variant.id})

      assert html =~ ~s(maxlength="200")
    end

    test "card_message is preserved when switching to a different card",
         %{conn: conn, variant: variant, card_product: card_product, card_variant: card_variant} do
      large_variant =
        generate(product_variant(product_id: card_product.id, size: :large, draft: false))

      gift_order = generate(cart(state: :gift_options, gift: true, recipient_name: "Test"))

      CartLineItem.add_item!(%{
        cart_id: gift_order.id,
        product_variant_id: variant.id,
        quantity: 1
      })

      Cart.add_card!(gift_order, card_variant.id, authorize?: false)

      conn
      |> Plug.Test.init_test_session(%{cart_id: gift_order.id})
      |> visit("/checkout")
      |> fill_in("Card Message", with: "Happy birthday!")
      |> assert_has("[data-testid='card-message-textarea']", text: "Happy birthday!")
      |> unwrap(fn view ->
        render_click(view, "select_card", %{"variant-id" => large_variant.id})
      end)
      |> assert_has("[data-testid='card-message-textarea']", text: "Happy birthday!")
    end

    test "submitting an oversize message renders the inline error",
         %{conn: conn, variant: variant, card_variant: card_variant} do
      gift_order = generate(cart(state: :gift_options, gift: true, recipient_name: "Test"))

      CartLineItem.add_item!(%{
        cart_id: gift_order.id,
        product_variant_id: variant.id,
        quantity: 1
      })

      Cart.add_card!(gift_order, card_variant.id, authorize?: false)

      oversize = String.duplicate("a", 81)

      conn
      |> Plug.Test.init_test_session(%{cart_id: gift_order.id})
      |> visit("/checkout")
      |> fill_in("Card Message", with: oversize)
      |> click_button("Next")
      |> assert_has("p", text: "at most")
    end

    test "remove_card clears card_message on the order",
         %{conn: conn, variant: variant, card_variant: card_variant} do
      gift_order =
        generate(cart(state: :gift_options, gift: true, recipient_name: "Test", card_message: "Pre-existing"))

      CartLineItem.add_item!(%{
        cart_id: gift_order.id,
        product_variant_id: variant.id,
        quantity: 1
      })

      Cart.add_card!(gift_order, card_variant.id, authorize?: false)

      conn
      |> Plug.Test.init_test_session(%{cart_id: gift_order.id})
      |> visit("/checkout")
      |> click_button("[data-testid='remove-card-button']", "Remove card")

      reloaded = Cart.get_for_checkout!(gift_order.id, actor: nil)
      assert is_nil(reloaded.card_message)
    end
  end

  describe "Cart-empty reset" do
    setup %{order: order} do
      cards_category = generate(product_category(slug: "cards", draft: false))
      tax_rate_ = generate(tax_rate())

      card_product =
        generate(product(product_category_id: cards_category.id, tax_rate_id: tax_rate_.id, draft: false))

      card_variant =
        generate(product_variant(product_id: card_product.id, size: :small, draft: false))

      %{order: order, card_variant: card_variant}
    end

    test "mounting with a card-only cart resets the order and redirects to home",
         %{conn: conn, order: order, card_variant: card_variant} do
      # Set up a stale checkout: customer made it to step 3 with all their
      # details filled in, then removed every product, leaving only a card.
      Cart.add_card!(order, card_variant.id, authorize?: false)
      [non_card_line_item] = Enum.reject(order.line_items, & &1.is_card)
      CartLineItem.remove_item!(non_card_line_item)

      stale =
        order
        |> Ash.Changeset.for_update(:submit_contact_details, %{
          customer_name: "Stale Customer",
          customer_email: "stale@example.com"
        })
        |> Ash.update!(authorize?: false)

      conn = Plug.Test.init_test_session(conn, %{cart_id: stale.id})

      log =
        capture_log(fn ->
          assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, "/checkout")
        end)

      assert log =~ "Cart is empty"

      reloaded = Cart.get_for_checkout!(stale.id, actor: nil)
      assert reloaded.line_items == []
      assert is_nil(reloaded.customer_name)
      assert reloaded.state == :contact_details
    end

    test "removing the last non-card line item mid-checkout resets the order and redirects",
         %{conn: conn, order: order, card_variant: card_variant} do
      Cart.add_card!(order, card_variant.id, authorize?: false)
      [non_card_line_item] = Enum.reject(order.line_items, & &1.is_card)

      conn = Plug.Test.init_test_session(conn, %{cart_id: order.id})
      {:ok, view, _html} = live(conn, "/checkout")

      CartLineItem.remove_item!(non_card_line_item)
      assert_redirect(view, "/")

      reloaded = Cart.get_for_checkout!(order.id, actor: nil)
      assert reloaded.line_items == []
    end
  end
end
