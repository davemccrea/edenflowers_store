defmodule EdenflowersWeb.CheckoutHappyPathTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator
  import Mox
  import Swoosh.TestAssertions
  import ExUnit.CaptureLog

  alias Edenflowers.Store.Order

  setup :verify_on_exit!

  setup %{conn: conn} do
    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    variant = generate(product_variant(product_id: product.id))

    fulfillment_option =
      generate(
        fulfillment_option(
          tax_rate_id: tax_rate.id,
          fulfillment_method: :pickup,
          rate_type: :fixed,
          base_price: "0.00"
        )
      )

    order = generate(order())

    Order.add_line_item!(order, variant.id, 1, authorize?: false)

    payment_intent = %{
      id: "pi_test_#{:rand.uniform(1_000_000)}",
      client_secret: "pi_test_secret_#{:rand.uniform(1_000_000)}"
    }

    stub(Edenflowers.StripeAPI.Mock, :create_payment_intent, fn _order -> {:ok, payment_intent} end)
    stub(Edenflowers.StripeAPI.Mock, :retrieve_payment_intent, fn _order -> {:ok, payment_intent} end)
    stub(Edenflowers.StripeAPI.Mock, :update_payment_intent, fn _order -> {:ok, payment_intent} end)

    conn = Plug.Test.init_test_session(conn, %{order_id: order.id})

    %{conn: conn, order: order, fulfillment_option: fulfillment_option}
  end

  test "completes a pickup checkout from step 1 through payment to confirmation email", %{
    conn: conn,
    order: order,
    fulfillment_option: fulfillment_option
  } do
    {:ok, view, _html} = live(conn, ~p"/checkout")

    # Step 1: Your Details
    view
    |> form("#checkout-form-1", %{
      "form" => %{
        "customer_name" => "Jane Doe",
        "customer_email" => "jane@example.com"
      }
    })
    |> render_submit()

    assert render(view) =~ "Gift options"

    # Step 2: Gift Options (not a gift — defaults are fine)
    view
    |> form("#checkout-form-2", %{"form" => %{"gift" => "false"}})
    |> render_submit()

    assert render(view) =~ ~r{<h2[^>]*>\s*Delivery\s*</h2>}

    # Step 3: pick fulfillment option, then submit the date/phone form
    view
    |> element("#checkout-form-3a")
    |> render_change(%{"form" => %{"fulfillment_option_id" => fulfillment_option.id}})

    fulfillment_date = Date.utc_today() |> Date.add(7) |> Date.to_string()

    view
    |> element("#checkout-form-3b")
    |> render_submit(%{
      "form" => %{
        "recipient_phone_number" => "045 1234567",
        "fulfillment_date" => fulfillment_date
      }
    })

    assert render(view) =~ "Payment"

    # Step 4: submit the payment form. In production, the Stripe JS hook
    # handles the confirmation; here the mocked update_payment_intent is
    # what the server touches. The webhook below drives the rest.
    view
    |> element("#checkout-form-4")
    |> render_submit()

    # Simulate Stripe firing payment_intent.succeeded — this finalizes the
    # order and enqueues the confirmation email Oban job.
    assert :ok =
             EdenflowersWeb.StripeHandler.handle_event(%Stripe.Event{
               type: "payment_intent.succeeded",
               data: %{object: %{metadata: %{"order_id" => order.id}}}
             })

    finalized = Order.get_by_id!(order.id, authorize?: false)
    assert finalized.state == :placed
    assert finalized.payment_status == :paid

    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :default)

    assert_email_sent(fn email ->
      assert email.to == [{"", "jane@example.com"}]
      assert email.subject =~ "Order Confirmation"
      assert email.subject =~ finalized.order_reference
    end)
  end

  test "completes a gift pickup checkout with a card and card message", %{
    conn: conn,
    order: order,
    fulfillment_option: fulfillment_option
  } do
    # Seed a cards category + card product/variant so the card drawer has
    # something to pick.
    cards_category = generate(product_category(slug: "cards", visibility: :public))
    card_tax_rate = generate(tax_rate())

    card_product =
      generate(
        product(
          product_category_id: cards_category.id,
          tax_rate_id: card_tax_rate.id,
          draft: false
        )
      )

    card_variant =
      generate(product_variant(product_id: card_product.id, size: :small, draft: false))

    {:ok, view, _html} = live(conn, ~p"/checkout")

    # Step 1
    view
    |> form("#checkout-form-1", %{
      "form" => %{
        "customer_name" => "Jane Doe",
        "customer_email" => "jane@example.com"
      }
    })
    |> render_submit()

    # Step 2: mark as gift (this fires `set_gift` and persists the flag so
    # the `add_card` policy passes), pick a card, write a card message,
    # submit.
    view
    |> element(~s(input[name="form[gift]"][value="true"]))
    |> render_change(%{"form" => %{"gift" => "true"}})

    view
    |> render_click("select_card", %{"variant-id" => card_variant.id})

    assert render(view) =~ ~s(data-testid="card-message-textarea")

    view
    |> form("#checkout-form-2", %{
      "form" => %{
        "gift" => "true",
        "recipient_name" => "John Recipient",
        "card_message" => "Happy birthday!"
      }
    })
    |> render_submit()

    assert render(view) =~ ~r{<h2[^>]*>\s*Delivery\s*</h2>}

    # Step 3
    view
    |> element("#checkout-form-3a")
    |> render_change(%{"form" => %{"fulfillment_option_id" => fulfillment_option.id}})

    fulfillment_date = Date.utc_today() |> Date.add(7) |> Date.to_string()

    view
    |> element("#checkout-form-3b")
    |> render_submit(%{
      "form" => %{
        "recipient_phone_number" => "045 1234567",
        "fulfillment_date" => fulfillment_date
      }
    })

    assert render(view) =~ "Payment"

    # Step 4
    view
    |> element("#checkout-form-4")
    |> render_submit()

    assert :ok =
             EdenflowersWeb.StripeHandler.handle_event(%Stripe.Event{
               type: "payment_intent.succeeded",
               data: %{object: %{metadata: %{"order_id" => order.id}}}
             })

    finalized =
      Order.get_by_id!(order.id, authorize?: false)
      |> Ash.load!([:line_items], authorize?: false)

    assert finalized.state == :placed
    assert finalized.payment_status == :paid
    assert finalized.gift == true
    assert finalized.recipient_name == "John Recipient"
    assert finalized.card_message == "Happy birthday!"
    assert Enum.any?(finalized.line_items, & &1.is_card)

    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :default)

    assert_email_sent(fn email ->
      assert email.to == [{"", "jane@example.com"}]
      assert email.subject =~ "Order Confirmation"
      assert email.subject =~ finalized.order_reference
    end)
  end

  test "completes a delivery checkout with a geocoded address", %{conn: conn, order: order} do
    # Seed a delivery fulfillment option (the shared setup's pickup option
    # is unused in this test).
    delivery_option =
      generate(
        fulfillment_option(
          fulfillment_method: :delivery,
          rate_type: :fixed,
          base_price: "5.00"
        )
      )

    stub(Edenflowers.HereAPI.Mock, :get_address, fn _query ->
      {:ok, {"Stadsgatan 3, 65300 Vasa", "63.0951,21.6165", "here-id-123"}}
    end)

    stub(Edenflowers.HereAPI.Mock, :get_distance, fn _position -> {:ok, 3000} end)

    {:ok, view, _html} = live(conn, ~p"/checkout")

    # Step 1
    view
    |> form("#checkout-form-1", %{
      "form" => %{
        "customer_name" => "Jane Doe",
        "customer_email" => "jane@example.com"
      }
    })
    |> render_submit()

    # Step 2
    view
    |> form("#checkout-form-2", %{"form" => %{"gift" => "false"}})
    |> render_submit()

    # Step 3: pick delivery, blur the address to trigger geocoding, submit
    view
    |> element("#checkout-form-3a")
    |> render_change(%{"form" => %{"fulfillment_option_id" => delivery_option.id}})

    view
    |> element("#address-input-field")
    |> render_blur(%{"value" => "Stadsgatan 3, 65300 Vasa"})

    render_async(view)

    fulfillment_date = Date.utc_today() |> Date.add(7) |> Date.to_string()

    view
    |> element("#checkout-form-3b")
    |> render_submit(%{
      "form" => %{
        "delivery_address" => "Stadsgatan 3, 65300 Vasa",
        "recipient_phone_number" => "045 1234567",
        "delivery_instructions" => "Leave at back door",
        "fulfillment_date" => fulfillment_date
      }
    })

    assert render(view) =~ "Payment"

    # Step 4
    view
    |> element("#checkout-form-4")
    |> render_submit()

    assert :ok =
             EdenflowersWeb.StripeHandler.handle_event(%Stripe.Event{
               type: "payment_intent.succeeded",
               data: %{object: %{metadata: %{"order_id" => order.id}}}
             })

    finalized = Order.get_by_id!(order.id, authorize?: false)

    assert finalized.state == :placed
    assert finalized.payment_status == :paid
    assert finalized.fulfillment_method == :delivery
    assert finalized.delivery_address == "Stadsgatan 3, 65300 Vasa"
    assert finalized.geocoded_address == "Stadsgatan 3, 65300 Vasa"
    assert finalized.here_id == "here-id-123"
    assert finalized.position == "63.0951,21.6165"
    assert finalized.distance == 3000
    assert Decimal.eq?(finalized.fulfillment_amount, Decimal.new("5.00"))
    assert finalized.delivery_instructions == "Leave at back door"

    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :default)

    assert_email_sent(fn email ->
      assert email.to == [{"", "jane@example.com"}]
      assert email.subject =~ "Order Confirmation"
      assert email.subject =~ finalized.order_reference
      assert email.text_body =~ "Stadsgatan 3, 65300 Vasa"
    end)
  end

  test "applies a promo code and the finalized order reflects the discount", %{
    conn: conn,
    order: order,
    fulfillment_option: fulfillment_option
  } do
    promotion = generate(promotion(code: "SAVE20", discount_percentage: "0.20"))

    {:ok, view, _html} = live(conn, ~p"/checkout")

    # Apply promo from the cart drawer (available at any step). The promo
    # input is collapsed behind a "Have a promo code?" toggle by default,
    # so click that first to reveal the form.
    view
    |> element("#cart-drawer-promo [data-testid='promo-toggle']")
    |> render_click()

    view
    |> form("#cart-drawer-promo-form", %{"form" => %{"code" => promotion.code}})
    |> render_submit()

    assert render(view) =~ ~s(data-testid="promo-badge")

    # Step 1 → 4
    view
    |> form("#checkout-form-1", %{
      "form" => %{
        "customer_name" => "Jane Doe",
        "customer_email" => "jane@example.com"
      }
    })
    |> render_submit()

    view
    |> form("#checkout-form-2", %{"form" => %{"gift" => "false"}})
    |> render_submit()

    view
    |> element("#checkout-form-3a")
    |> render_change(%{"form" => %{"fulfillment_option_id" => fulfillment_option.id}})

    fulfillment_date = Date.utc_today() |> Date.add(7) |> Date.to_string()

    view
    |> element("#checkout-form-3b")
    |> render_submit(%{
      "form" => %{
        "recipient_phone_number" => "045 1234567",
        "fulfillment_date" => fulfillment_date
      }
    })

    view
    |> element("#checkout-form-4")
    |> render_submit()

    assert :ok =
             EdenflowersWeb.StripeHandler.handle_event(%Stripe.Event{
               type: "payment_intent.succeeded",
               data: %{object: %{metadata: %{"order_id" => order.id}}}
             })

    finalized =
      Order.get_by_id!(order.id, authorize?: false)
      |> Ash.load!([:promotion_applied?, :discount_amount, :total, :promotion], authorize?: false)

    assert finalized.state == :placed
    assert finalized.promotion_applied?
    assert to_string(finalized.promotion.code) == "SAVE20"
    # €35.00 line total × 20% = €7.00 discount
    assert Decimal.eq?(finalized.discount_amount, Decimal.new("7.00"))

    # Two jobs run on a promo order: the confirmation email and the
    # promotion-usage increment.
    assert %{success: 2, failure: 0} = Oban.drain_queue(queue: :default)

    assert_email_sent(fn email ->
      # The template renders the discount line, not the promo code itself.
      assert email.text_body =~ "Discount"
      assert email.text_body =~ "-€7.00"
      assert email.text_body =~ "Total: €28.00"
    end)
  end

  test "applying a promo code preserves unsaved values typed into the current step", %{
    conn: conn
  } do
    promotion = generate(promotion(code: "SAVE20", discount_percentage: "0.20"))

    {:ok, view, _html} = live(conn, ~p"/checkout")

    # Type into step 1 without submitting — phx-change ships the values
    # to the server so they live on the form's params.
    view
    |> form("#checkout-form-1", %{
      "form" => %{
        "customer_name" => "Jane Doe",
        "customer_email" => "jane@example.com"
      }
    })
    |> render_change()

    # Apply the promo from the cart drawer. The promo input is collapsed
    # behind a "Have a promo code?" toggle by default, so click that first
    # to reveal the form.
    view
    |> element("#cart-drawer-promo [data-testid='promo-toggle']")
    |> render_click()

    view
    |> form("#cart-drawer-promo-form", %{"form" => %{"code" => promotion.code}})
    |> render_submit()

    # Render again so the broadcast-triggered handle_info has been processed
    # and the parent LiveView has reloaded with the applied promo.
    html = render(view)

    assert html =~ ~s(data-testid="promo-badge")
    assert html =~ "Jane Doe"
    assert html =~ "jane@example.com"
  end

  test "selecting a card preserves the unsaved recipient name on step 2", %{conn: conn} do
    cards_category = generate(product_category(slug: "cards", visibility: :public))
    card_tax_rate = generate(tax_rate())

    card_product =
      generate(
        product(
          product_category_id: cards_category.id,
          tax_rate_id: card_tax_rate.id,
          draft: false
        )
      )

    card_variant =
      generate(product_variant(product_id: card_product.id, size: :small, draft: false))

    {:ok, view, _html} = live(conn, ~p"/checkout")

    # Step 1
    view
    |> form("#checkout-form-1", %{
      "form" => %{
        "customer_name" => "Jane Doe",
        "customer_email" => "jane@example.com"
      }
    })
    |> render_submit()

    # Mark as gift so the card-selection UI is rendered.
    view
    |> element(~s(input[name="form[gift]"][value="true"]))
    |> render_change(%{"form" => %{"gift" => "true"}})

    # Type a recipient name without submitting — phx-change ships it to
    # the server so it lives on the form's params.
    view
    |> form("#checkout-form-2", %{
      "form" => %{
        "gift" => "true",
        "recipient_name" => "John Recipient"
      }
    })
    |> render_change()

    # Pick a card.
    html =
      view
      |> render_click("select_card", %{"variant-id" => card_variant.id})

    assert html =~ ~s(data-testid="card-message-textarea")
    assert html =~ "John Recipient"
  end

  test "Stripe failure on step 4 keeps the order in checkout and sends no email", %{
    conn: conn,
    order: order,
    fulfillment_option: fulfillment_option
  } do
    # Override the stub from setup: update_payment_intent now fails.
    stub(Edenflowers.StripeAPI.Mock, :update_payment_intent, fn _order ->
      {:error, :stripe_down}
    end)

    {:ok, view, _html} = live(conn, ~p"/checkout")

    view
    |> form("#checkout-form-1", %{
      "form" => %{
        "customer_name" => "Jane Doe",
        "customer_email" => "jane@example.com"
      }
    })
    |> render_submit()

    view
    |> form("#checkout-form-2", %{"form" => %{"gift" => "false"}})
    |> render_submit()

    view
    |> element("#checkout-form-3a")
    |> render_change(%{"form" => %{"fulfillment_option_id" => fulfillment_option.id}})

    fulfillment_date = Date.utc_today() |> Date.add(7) |> Date.to_string()

    view
    |> element("#checkout-form-3b")
    |> render_submit(%{
      "form" => %{
        "recipient_phone_number" => "045 1234567",
        "fulfillment_date" => fulfillment_date
      }
    })

    {html, log} =
      with_log(fn ->
        view
        |> element("#checkout-form-4")
        |> render_submit()
      end)

    assert html =~ "Payment processing error"
    assert log =~ "Failed to update payment intent"

    stalled = Order.get_by_id!(order.id, authorize?: false)
    assert stalled.state == :payment
    assert stalled.payment_status != :paid

    assert %{success: 0, failure: 0} = Oban.drain_queue(queue: :default)

    refute_email_sent()
  end
end
