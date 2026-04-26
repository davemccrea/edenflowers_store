defmodule EdenflowersWeb.CheckoutLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import PhoenixTest
  import Phoenix.LiveViewTest, only: [live: 2, render_click: 3]
  import Generator
  import Mox

  alias Edenflowers.Store.{Order, LineItem}

  setup :verify_on_exit!

  setup do
    product = generate(product())
    variant = generate(product_variant(%{product_id: product.id}))
    generate(fulfillment_option())

    order = generate(order())

    {:ok, _line_item} =
      LineItem.add_item(%{
        order_id: order.id,
        product_variant_id: variant.id,
        quantity: 1,
      })

    order = Order.get_for_checkout!(order.id, actor: nil)

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
      session =
        conn
        |> Plug.Test.init_test_session(%{order_id: order.id})
        |> visit("/checkout")
        |> fill_in("Your Name *", with: "John Doe")
        |> fill_in("Email *", with: "john@example.com")
        |> click_button("Next")

      %{session: session}
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
        product_variant_id: variant.id,
        quantity: 1,
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

    test "LineItem.add_card succeeds for gift orders", %{
      order: order,
      card_product: card_product,
      card_variant: card_variant
    } do
      order
      |> Ash.Changeset.for_update(:set_gift, %{gift: true})
      |> Ash.update!(authorize?: false)

      assert {:ok, card_line_item} =
               LineItem.add_card(%{
                 order_id: order.id,
                 product_variant_id: card_variant.id,
                 quantity: 1,
               })

      assert card_line_item.is_card == true
    end

    test "LineItem.add_card returns an error for non-gift orders", %{
      order: order,
      card_product: card_product,
      card_variant: card_variant
    } do
      assert {:error, _} =
               LineItem.add_card(%{
                 order_id: order.id,
                 product_variant_id: card_variant.id,
                 quantity: 1,
               })
    end

    test "saving step 2 with gift=false removes card line items", %{
      order: order,
      card_product: card_product,
      card_variant: card_variant
    } do
      order =
        order
        |> Ash.Changeset.for_update(:set_gift, %{gift: true})
        |> Ash.update!(authorize?: false)

      {:ok, _card} =
        LineItem.add_card(%{
          order_id: order.id,
          product_variant_id: card_variant.id,
          quantity: 1,
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
        product_variant_id: variant.id,
        quantity: 1,
      })

      LineItem.add_card!(
        %{
          order_id: gift_order.id,
          product_variant_id: card_variant.id,
          quantity: 1,
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
        product_variant_id: variant.id,
        quantity: 1,
      })

      conn
      |> Plug.Test.init_test_session(%{order_id: gift_order.id})
      |> visit("/checkout")
      |> assert_has("[data-testid='select-card-button']")
      |> click_button("[data-testid='card-option-#{card_variant.id}']", card_product.name)
      |> assert_has("[data-testid='card-message-textarea']")
      |> refute_has("[data-testid='select-card-button']")
    end

    test "remove_card event removes the card from the order",
         %{conn: conn, product: product, variant: variant, card_product: card_product, card_variant: card_variant} do
      gift_order = generate(order(step: 2, gift: true))

      LineItem.add_item!(%{
        order_id: gift_order.id,
        product_variant_id: variant.id,
        quantity: 1,
      })

      LineItem.add_card!(
        %{
          order_id: gift_order.id,
          product_variant_id: card_variant.id,
          quantity: 1,
        },
        authorize?: false
      )

      conn
      |> Plug.Test.init_test_session(%{order_id: gift_order.id})
      |> visit("/checkout")
      |> assert_has("[data-testid='card-message-textarea']")
      |> click_button("[data-testid='remove-card-button']", "Remove card")
      |> assert_has("[data-testid='select-card-button']")
      |> refute_has("[data-testid='card-message-textarea']")
    end

    test "save_form_2 persists card_message on the order",
         %{conn: conn, product: product, variant: variant, card_product: card_product, card_variant: card_variant} do
      # recipient_name is required when gift=true, so seed it on the order directly
      gift_order = generate(order(step: 2, gift: true, recipient_name: "Test Recipient"))

      LineItem.add_item!(%{
        order_id: gift_order.id,
        product_variant_id: variant.id,
        quantity: 1,
      })

      LineItem.add_card!(
        %{
          order_id: gift_order.id,
          product_variant_id: card_variant.id,
          quantity: 1,
        },
        authorize?: false
      )

      conn
      |> Plug.Test.init_test_session(%{order_id: gift_order.id})
      |> visit("/checkout")
      |> fill_in("Card Message", with: "Happy birthday!")
      |> click_button("Next")

      reloaded = Order.get_for_checkout!(gift_order.id, actor: nil)
      assert reloaded.card_message == "Happy birthday!"
    end

    test "card_message is preserved across re-renders while on step 2",
         %{conn: conn, product: product, variant: variant, card_product: card_product, card_variant: card_variant} do
      gift_order = generate(order(step: 2, gift: true, recipient_name: "Original"))

      LineItem.add_item!(%{
        order_id: gift_order.id,
        product_variant_id: variant.id,
        quantity: 1,
      })

      LineItem.add_card!(
        %{
          order_id: gift_order.id,
          product_variant_id: card_variant.id,
          quantity: 1,
        },
        authorize?: false
      )

      conn
      |> Plug.Test.init_test_session(%{order_id: gift_order.id})
      |> visit("/checkout")
      |> fill_in("Card Message", with: "Happy birthday!")
      |> fill_in("Recipient Name *", with: "Updated Recipient")
      |> assert_has("[data-testid='card-message-textarea']", text: "Happy birthday!")
    end

    test "renders maxlength matching the selected card's size limit",
         %{conn: conn, product: product, variant: variant, card_product: card_product, card_variant: card_variant} do
      gift_order = generate(order(step: 2, gift: true, recipient_name: "Test"))

      LineItem.add_item!(%{
        order_id: gift_order.id,
        product_variant_id: variant.id,
        quantity: 1,
      })

      LineItem.add_card!(
        %{
          order_id: gift_order.id,
          product_variant_id: card_variant.id,
          quantity: 1,
        },
        authorize?: false
      )

      {:ok, _view, html} =
        conn
        |> Plug.Test.init_test_session(%{order_id: gift_order.id})
        |> live("/checkout")

      assert html =~ ~s(maxlength="80")
    end

    test "switching from small to large card updates the rendered limit",
         %{conn: conn, product: product, variant: variant, card_product: card_product, card_variant: card_variant} do
      large_variant =
        generate(product_variant(product_id: card_product.id, size: :large, draft: false))

      gift_order = generate(order(step: 2, gift: true, recipient_name: "Test"))

      LineItem.add_item!(%{
        order_id: gift_order.id,
        product_variant_id: variant.id,
        quantity: 1,
      })

      LineItem.add_card!(
        %{
          order_id: gift_order.id,
          product_variant_id: card_variant.id,
          quantity: 1,
        },
        authorize?: false
      )

      {:ok, view, html} =
        conn
        |> Plug.Test.init_test_session(%{order_id: gift_order.id})
        |> live("/checkout")

      assert html =~ ~s(maxlength="80")

      html = render_click(view, "select_card", %{"variant-id" => large_variant.id})

      assert html =~ ~s(maxlength="200")
    end

    test "card_message is preserved when switching to a different card",
         %{conn: conn, product: product, variant: variant, card_product: card_product, card_variant: card_variant} do
      large_variant =
        generate(product_variant(product_id: card_product.id, size: :large, draft: false))

      gift_order = generate(order(step: 2, gift: true, recipient_name: "Test"))

      LineItem.add_item!(%{
        order_id: gift_order.id,
        product_variant_id: variant.id,
        quantity: 1,
      })

      LineItem.add_card!(
        %{
          order_id: gift_order.id,
          product_variant_id: card_variant.id,
          quantity: 1,
        },
        authorize?: false
      )

      conn
      |> Plug.Test.init_test_session(%{order_id: gift_order.id})
      |> visit("/checkout")
      |> fill_in("Card Message", with: "Happy birthday!")
      |> assert_has("[data-testid='card-message-textarea']", text: "Happy birthday!")
      |> unwrap(fn view ->
        render_click(view, "select_card", %{"variant-id" => large_variant.id})
      end)
      |> assert_has("[data-testid='card-message-textarea']", text: "Happy birthday!")
    end

    test "submitting an oversize message renders the inline error",
         %{conn: conn, product: product, variant: variant, card_product: card_product, card_variant: card_variant} do
      gift_order = generate(order(step: 2, gift: true, recipient_name: "Test"))

      LineItem.add_item!(%{
        order_id: gift_order.id,
        product_variant_id: variant.id,
        quantity: 1,
      })

      LineItem.add_card!(
        %{
          order_id: gift_order.id,
          product_variant_id: card_variant.id,
          quantity: 1,
        },
        authorize?: false
      )

      oversize = String.duplicate("a", 81)

      conn
      |> Plug.Test.init_test_session(%{order_id: gift_order.id})
      |> visit("/checkout")
      |> fill_in("Card Message", with: oversize)
      |> click_button("Next")
      |> assert_has("p", text: "at most")
    end

    test "remove_card clears card_message on the order",
         %{conn: conn, product: product, variant: variant, card_product: card_product, card_variant: card_variant} do
      gift_order =
        generate(order(step: 2, gift: true, recipient_name: "Test", card_message: "Pre-existing"))

      LineItem.add_item!(%{
        order_id: gift_order.id,
        product_variant_id: variant.id,
        quantity: 1,
      })

      LineItem.add_card!(
        %{
          order_id: gift_order.id,
          product_variant_id: card_variant.id,
          quantity: 1,
        },
        authorize?: false
      )

      conn
      |> Plug.Test.init_test_session(%{order_id: gift_order.id})
      |> visit("/checkout")
      |> click_button("[data-testid='remove-card-button']", "Remove card")

      reloaded = Order.get_for_checkout!(gift_order.id, actor: nil)
      assert is_nil(reloaded.card_message)
    end
  end
end
