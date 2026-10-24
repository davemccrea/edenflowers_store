defmodule EdenflowersWeb.Checkout.CheckoutLiveTest do
  use EdenflowersWeb.ConnCase, async: true
  use Oban.Testing, repo: Edenflowers.Repo

  import PhoenixTest

  import Phoenix.LiveViewTest,
    only: [
      element: 3,
      live: 2,
      render: 1,
      render_click: 1,
      render_change: 2,
      render_submit: 1,
      render_submit: 2,
      element: 2,
      assert_redirect: 3,
      assert_push_event: 3,
      assert_patch: 2,
      has_element?: 2,
      render_patch: 2,
      refute_push_event: 3
    ]

  import ExUnit.CaptureLog
  import Generator
  import Mox

  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders

  setup :verify_on_exit!

  setup do
    product = generate(product())
    variant = generate(product_variant(%{product_id: product.id}))
    generate(fulfillment_option())

    order = generate(order())

    {:ok, _order} = Orders.add_line_item(order.id, variant.id, 1, authorize?: false)

    order = Orders.get_order_for_checkout!(order.id, actor: nil)

    mock_payment_intent = %{
      id: "pi_test_#{:rand.uniform(1_000_000)}",
      client_secret: "pi_test_secret_#{:rand.uniform(1_000_000)}"
    }

    stub(Edenflowers.External.StripeAPI.Mock, :create_payment_intent, fn _amount, _metadata, _customer ->
      {:ok, mock_payment_intent}
    end)

    stub(Edenflowers.External.StripeAPI.Mock, :retrieve_payment_intent, fn _order ->
      {:ok, mock_payment_intent}
    end)

    stub(Edenflowers.External.StripeAPI.Mock, :update_payment_intent, fn _payment_intent_id, _amount_cents ->
      {:ok, mock_payment_intent}
    end)

    %{order: order, product: product, variant: variant}
  end

  describe "paying" do
    setup %{variant: variant} do
      order = generate(order(state: :payment, customer_name: "Jane Doe", customer_email: "jane@example.com"))
      Orders.add_line_item!(order.id, variant.id, 1, authorize?: false)
      %{order: Orders.get_order_for_checkout!(order.id, actor: nil)}
    end

    test "shows the Payment Element the total before any PaymentIntent exists", %{conn: conn, order: order} do
      {:ok, view, _html} = live(Plug.Test.init_test_session(conn, %{order_id: order.id}), ~p"/checkout")

      amount = StripeAPI.to_stripe_amount(order.grand_total)
      assert has_element?(view, ~s|#checkout-form-4[data-amount="#{amount}"]|)
      assert is_nil(Orders.get_order_by_id!(order.id, authorize?: false).payment_intent_id)
    end

    test "creates the PaymentIntent at the total, and reuses it when paying again", %{conn: conn, order: order} do
      amount = StripeAPI.to_stripe_amount(order.grand_total)

      expect(Edenflowers.External.StripeAPI.Mock, :create_payment_intent, fn ^amount, _metadata, _customer ->
        {:ok, %{id: "pi_jane", client_secret: "pi_jane_secret", amount: amount}}
      end)

      expect(Edenflowers.External.StripeAPI.Mock, :update_payment_intent, fn "pi_jane", ^amount -> {:ok, %{}} end)

      expect(Edenflowers.External.StripeAPI.Mock, :retrieve_payment_intent, fn _order ->
        {:ok, %{id: "pi_jane", client_secret: "pi_jane_secret"}}
      end)

      {:ok, view, _html} = live(Plug.Test.init_test_session(conn, %{order_id: order.id}), ~p"/checkout")

      view |> element("#checkout-form-4") |> render_submit()
      assert_push_event(view, "stripe:process_payment", %{client_secret: "pi_jane_secret"})

      view |> element("#checkout-form-4") |> render_submit()
      assert_push_event(view, "stripe:process_payment", %{client_secret: "pi_jane_secret"})
    end

    test "a subscription saves its card and replaces a one-off PaymentIntent", %{conn: conn} do
      product = generate(product(subscribable: true, free_delivery: true))
      subscribable = generate(product_variant(product_id: product.id))

      order =
        generate(
          order(
            state: :payment,
            customer_name: "Jane Doe",
            customer_email: "jane@example.com",
            payment_intent_id: "pi_one_off"
          )
        )

      Orders.add_line_item!(order.id, subscribable.id, 1, authorize?: false)

      stub(Edenflowers.External.StripeAPI.Mock, :retrieve_payment_intent, fn _order ->
        {:ok, %{id: "pi_one_off", client_secret: "pi_one_off_secret"}}
      end)

      expect(Edenflowers.External.StripeAPI.Mock, :cancel_payment_intent, fn intent -> {:ok, intent} end)
      expect(Edenflowers.External.StripeAPI.Mock, :create_customer, fn _params -> {:ok, %{id: "cus_jane"}} end)

      expect(Edenflowers.External.StripeAPI.Mock, :create_payment_intent_saving_card, fn _amount,
                                                                                         _metadata,
                                                                                         "cus_jane" ->
        {:ok, %{id: "pi_subscription", client_secret: "subscription_secret", amount: 0}}
      end)

      {:ok, view, _html} = live(Plug.Test.init_test_session(conn, %{order_id: order.id}), ~p"/checkout")
      refute has_element?(view, "#checkout-form-4[data-setup-future-usage]")

      Orders.add_line_item!(order.id, subscribable.id, 1, %{interval_weeks: 2}, authorize?: false)
      assert has_element?(view, ~s|#checkout-form-4[data-setup-future-usage="off_session"]|)

      view |> element("#checkout-form-4") |> render_submit()

      assert_push_event(view, "stripe:process_payment", %{client_secret: "subscription_secret"})
      assert Orders.get_order_by_id!(order.id, authorize?: false).payment_intent_id == "pi_subscription"
    end
  end

  describe "saved cards" do
    setup %{variant: variant} do
      order = generate(order(state: :payment, customer_name: "Ada Lovelace", customer_email: "ada@example.com"))
      Orders.add_line_item!(order.id, variant.id, 1, authorize?: false)
      %{order: order}
    end

    test "hands a signed-in customer's CustomerSession to the Payment Element", %{conn: conn, order: order} do
      user = with_token(generate(admin_user(admin: false, email: "ada@example.com")))

      expect(Edenflowers.External.StripeAPI.Mock, :create_customer, fn _params -> {:ok, %{id: "cus_ada"}} end)

      expect(Edenflowers.External.StripeAPI.Mock, :create_customer_session, fn "cus_ada" ->
        {:ok, %{client_secret: "cuss_ada"}}
      end)

      {:ok, view, _html} =
        conn
        |> Plug.Test.init_test_session(%{order_id: order.id})
        |> Helpers.store_in_session(user)
        |> live(~p"/checkout")

      assert render(view) =~ ~s|data-customer-session-client-secret="cuss_ada"|
    end

    test "gives a guest no CustomerSession", %{conn: conn, order: order} do
      {:ok, view, _html} = live(Plug.Test.init_test_session(conn, %{order_id: order.id}), ~p"/checkout")

      assert render(view) =~ "data-amount"
      refute render(view) =~ "data-customer-session-client-secret"
    end
  end

  describe "Step 1: Your Details" do
    test "prefills the name and email of a signed-in customer", %{conn: conn, order: order} do
      user = generate(admin_user(admin: false, name: "Ada Lovelace", email: "ada@example.com"))
      user = with_token(user)

      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> Helpers.store_in_session(user)
      |> visit("/checkout")
      |> assert_has("[data-testid=customer-name-input]", value: "Ada Lovelace")
      |> assert_has("[data-testid=customer-email-input]", value: "ada@example.com")
    end

    test "successfully submits and progresses to step 2", %{conn: conn, order: order} do
      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> visit("/checkout")
      |> fill_in("Your name *", with: "John Doe")
      |> fill_in("Email *", with: "john@example.com")
      |> click_button("Next")
      |> assert_has("h2", text: "Gift options")
    end

    test "rejects an invalid email and stays on step 1", %{conn: conn, order: order} do
      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> visit("/checkout")
      |> fill_in("Your name *", with: "John Doe")
      |> fill_in("Email *", with: "notanemail")
      |> click_button("Next")
      |> assert_has("p", text: "Must be a valid email address")

      reloaded = Orders.get_order_for_checkout!(order.id, actor: nil)
      assert reloaded.state == :contact_details
      assert is_nil(reloaded.customer_email)
    end

    test "newsletter checkbox is unchecked by default", %{conn: conn, order: order} do
      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> visit("/checkout")
      |> refute_has("[data-testid='newsletter-opt-in-checkbox'][checked]")
    end

    test "checking the newsletter box subscribes the user and enqueues the welcome email", %{
      conn: conn,
      order: order
    } do
      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> visit("/checkout")
      |> fill_in("Your name *", with: "Subscriber")
      |> fill_in("Email *", with: "subscriber@example.com")
      |> check("Subscribe to the newsletter to receive 15% off your first order by email.")
      |> click_button("Next")
      |> assert_has("h2", text: "Gift options")

      {:ok, user} = Edenflowers.Accounts.get_user_by_email("subscriber@example.com", authorize?: false)
      assert user.newsletter_opt_in == true

      assert_enqueued(
        worker: Edenflowers.Pricing.Workers.SendNewsletterPromoEmail,
        args: %{"email" => "subscriber@example.com"}
      )
    end

    test "leaving the newsletter box unchecked does not opt the user in", %{conn: conn, order: order} do
      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> visit("/checkout")
      |> fill_in("Your name *", with: "Bystander")
      |> fill_in("Email *", with: "bystander@example.com")
      |> click_button("Next")
      |> assert_has("h2", text: "Gift options")

      {:ok, user} = Edenflowers.Accounts.get_user_by_email("bystander@example.com", authorize?: false)
      assert user.newsletter_opt_in == false

      refute_enqueued(worker: Edenflowers.Pricing.Workers.SendNewsletterPromoEmail)
    end

    # The order carries the hide decision, as a guest can't read the subscribed user.
    test "newsletter checkbox is hidden after a guest opts in and returns to step 1", %{conn: conn, order: order} do
      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> visit("/checkout")
      |> fill_in("Your name *", with: "Returning Guest")
      |> fill_in("Email *", with: "returning@example.com")
      |> check("Subscribe to the newsletter to receive 15% off your first order by email.")
      |> click_button("Next")
      |> assert_has("h2", text: "Gift options")
      # click_button re-matches the name with a space before the sr-only ": Your details", so it never matches.
      |> unwrap(&(&1 |> element("button", "Edit") |> render_click()))
      |> assert_has("[data-testid='checkout-step-1']")
      |> refute_has("[data-testid='newsletter-opt-in-checkbox']")
    end

    # A guest who declined the offer should still see the box on return, since
    # nothing was stamped.
    test "newsletter checkbox stays visible after a guest declines and returns to step 1", %{
      conn: conn,
      order: order
    } do
      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> visit("/checkout")
      |> fill_in("Your name *", with: "Undecided Guest")
      |> fill_in("Email *", with: "undecided@example.com")
      |> click_button("Next")
      |> assert_has("h2", text: "Gift options")
      # click_button re-matches the name with a space before the sr-only ": Your details", so it never matches.
      |> unwrap(&(&1 |> element("button", "Edit") |> render_click()))
      |> assert_has("[data-testid='checkout-step-1']")
      |> assert_has("[data-testid='newsletter-opt-in-checkbox']")
    end

    # An order whose customer email resolves to an already-subscribed user gets
    # the box hidden on submit, even if the box itself was left unticked.
    test "newsletter checkbox is hidden once the order's user is already subscribed", %{conn: conn, order: order} do
      generate(admin_user(admin: false, email: "subscribed@example.com", newsletter_opt_in: true))

      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> visit("/checkout")
      |> fill_in("Your name *", with: "Already Subscribed")
      |> fill_in("Email *", with: "subscribed@example.com")
      |> click_button("Next")
      |> assert_has("h2", text: "Gift options")
      # click_button re-matches the name with a space before the sr-only ": Your details", so it never matches.
      |> unwrap(&(&1 |> element("button", "Edit") |> render_click()))
      |> assert_has("[data-testid='checkout-step-1']")
      |> refute_has("[data-testid='newsletter-opt-in-checkbox']")
    end

    test "a subscription cart says an account is made, and offers no first-order discount", %{conn: conn} do
      product = generate(product(subscribable: true, free_delivery: true))
      variant = generate(product_variant(product_id: product.id))
      order = generate(order())
      Orders.add_line_item!(order.id, variant.id, 1, %{interval_weeks: 2}, authorize?: false)

      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> visit("/checkout")
      |> assert_has("[data-testid='account-note']", text: "set up an account with this email")
      |> refute_has("[data-testid='newsletter-opt-in-checkbox']")
    end

    test "a subscription cart doesn't promise an account to a signed-in user", %{conn: conn} do
      product = generate(product(subscribable: true, free_delivery: true))
      variant = generate(product_variant(product_id: product.id))
      order = generate(order())
      Orders.add_line_item!(order.id, variant.id, 1, %{interval_weeks: 2}, authorize?: false)
      user = generate(admin_user(admin: false)) |> with_token()

      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> Helpers.store_in_session(user)
      |> visit("/checkout")
      |> assert_has("[data-testid='checkout-step-1']")
      |> refute_has("[data-testid='account-note']")
    end

    test "newsletter checkbox is hidden on arrival for a signed-in subscriber", %{conn: conn, order: order} do
      user = generate(admin_user(admin: false, newsletter_opt_in: true)) |> with_token()

      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> Helpers.store_in_session(user)
      |> visit("/checkout")
      |> assert_has("[data-testid='checkout-step-1']")
      |> refute_has("[data-testid='newsletter-opt-in-checkbox']")
    end

    test "newsletter checkbox is shown on arrival for a signed-in non-subscriber", %{conn: conn, order: order} do
      user = generate(admin_user(admin: false, newsletter_opt_in: false)) |> with_token()

      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> Helpers.store_in_session(user)
      |> visit("/checkout")
      |> assert_has("[data-testid='checkout-step-1']")
      |> assert_has("[data-testid='newsletter-opt-in-checkbox']")
    end
  end

  describe "Step 2: Gift Options" do
    setup %{conn: conn, order: order} do
      session =
        conn
        |> Plug.Test.init_test_session(%{order_id: order.id})
        |> visit("/checkout")
        |> fill_in("Your name *", with: "John Doe")
        |> fill_in("Email *", with: "john@example.com")
        |> click_button("Next")

      %{session: session}
    end

    test "successfully submits and progresses to step 3", %{session: session} do
      session
      |> click_button("Next")
      |> assert_has("h2", text: "Delivery")
    end

    test "shows step 3's inputs for the defaulted fulfillment option", %{session: session} do
      session
      |> click_button("Next")
      |> assert_has("#checkout-form-3b")
    end

    test "does not show 'Select a card' button when gift is false", %{session: session} do
      session
      |> refute_has("[data-testid='select-card-button']")
    end

    test "shows 'Add a card' button when order is a gift",
         %{conn: conn, variant: variant} do
      gift_order = generate(order(state: :gift_options, gift: true))

      Orders.add_line_item!(gift_order.id, variant.id, 1, authorize?: false)

      conn
      |> Plug.Test.init_test_session(%{order_id: gift_order.id})
      |> visit("/checkout")
      |> assert_has("[data-testid='select-card-button']")
    end

    test "a subscription gift says the card comes with the first delivery", %{conn: conn} do
      variant = generate(product_variant(product_id: generate(product(subscribable: true, free_delivery: true)).id))
      gift_order = generate(order(state: :gift_options, gift: true))
      Orders.add_line_item!(gift_order.id, variant.id, 1, %{interval_weeks: 2}, authorize?: false)

      conn
      |> Plug.Test.init_test_session(%{order_id: gift_order.id})
      |> visit("/checkout")
      |> assert_has("[data-testid='first-delivery-card']", text: "The card comes with your first delivery.")
    end

    test "a one-off gift says nothing about the first delivery", %{conn: conn, variant: variant} do
      gift_order = generate(order(state: :gift_options, gift: true))
      Orders.add_line_item!(gift_order.id, variant.id, 1, authorize?: false)

      conn
      |> Plug.Test.init_test_session(%{order_id: gift_order.id})
      |> visit("/checkout")
      |> assert_has("[data-testid='select-card-button']")
      |> refute_has("[data-testid='first-delivery-card']")
    end
  end

  describe "Card selection" do
    setup %{order: order} do
      cards_category = generate(product_category(slug: "cards", visibility: :public))
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
      order = generate(order(state: :gift_options, gift: true))
      Orders.add_card!(order, card_variant.id, authorize?: false, load: [:line_items])

      order
      |> Ash.Changeset.for_update(:submit_gift_options, %{gift: false})
      |> Ash.update!(authorize?: false)

      reloaded = Orders.get_order_for_checkout!(order.id, actor: nil)
      refute Enum.any?(reloaded.line_items, & &1.is_card)
    end

    test "shows card message textarea when a card line item exists",
         %{conn: conn, variant: variant, card_variant: card_variant} do
      gift_order = generate(order(state: :gift_options, gift: true))

      Orders.add_line_item!(gift_order.id, variant.id, 1, authorize?: false)

      Orders.add_card!(gift_order, card_variant.id, authorize?: false, load: [:line_items])

      conn
      |> Plug.Test.init_test_session(%{order_id: gift_order.id})
      |> visit("/checkout")
      |> assert_has("[data-testid='card-message-textarea']")
    end

    test "card row in cart sidebar has a remove control but no quantity controls",
         %{conn: conn, variant: variant, card_product: card_product, card_variant: card_variant} do
      gift_order = generate(order(state: :gift_options, gift: true))

      Orders.add_line_item!(gift_order.id, variant.id, 1, authorize?: false)

      card =
        Orders.add_card!(gift_order, card_variant.id, authorize?: false, load: [:line_items]).line_items
        |> Enum.find(& &1.is_card)

      conn
      |> Plug.Test.init_test_session(%{order_id: gift_order.id})
      |> visit("/checkout")
      # The card line item is rendered in the cart so the customer can see it
      # on the totals breakdown and remove it if they change their mind.
      |> assert_has("#checkout-line-items", text: card_product.name)
      |> assert_has("#checkout-line-items-remove-#{card.id}")
      # The checkout has the card picker, so the card line opens it.
      |> assert_has("[data-testid='cart-change-card-button']", text: card_product.name)
      # Cards are always quantity 1, so the +/- controls do not apply.
      |> refute_has("#checkout-line-items-increment-#{card.id}")
      |> refute_has("#checkout-line-items-decrement-#{card.id}")
    end

    test "select_card event adds a card line item to the order",
         %{conn: conn, variant: variant, card_product: card_product, card_variant: card_variant} do
      gift_order = generate(order(state: :gift_options, gift: true))

      Orders.add_line_item!(gift_order.id, variant.id, 1, authorize?: false)

      conn
      |> Plug.Test.init_test_session(%{order_id: gift_order.id})
      |> visit("/checkout")
      |> assert_has("[data-testid='select-card-button']")
      |> click_button("[data-testid='card-option-#{card_variant.id}']", card_product.name)
      |> assert_has("[data-testid='card-message-textarea']")
      |> refute_has("[data-testid='select-card-button']")
    end

    test "removing the card from the cart sidebar swaps the card message for the card picker",
         %{conn: conn, variant: variant, card_variant: card_variant} do
      gift_order = generate(order(state: :gift_options, gift: true))

      Orders.add_line_item!(gift_order.id, variant.id, 1, authorize?: false)

      card =
        Orders.add_card!(gift_order, card_variant.id, authorize?: false, load: [:line_items]).line_items
        |> Enum.find(& &1.is_card)

      {:ok, view, _html} =
        conn
        |> Plug.Test.init_test_session(%{order_id: gift_order.id})
        |> live("/checkout")

      view |> element("#checkout-line-items-remove-#{card.id}") |> render_click()
      # The checkout picks up the removal from the line_item:changed broadcast.
      html = render(view)

      assert html =~ ~s(data-testid="select-card-button")
      refute html =~ ~s(data-testid="card-message-textarea")
    end

    test "card_message is preserved across re-renders while on step 2",
         %{conn: conn, variant: variant, card_variant: card_variant} do
      gift_order = generate(order(state: :gift_options, gift: true, recipient_name: "Original"))

      Orders.add_line_item!(gift_order.id, variant.id, 1, authorize?: false)

      Orders.add_card!(gift_order, card_variant.id, authorize?: false, load: [:line_items])

      conn
      |> Plug.Test.init_test_session(%{order_id: gift_order.id})
      |> visit("/checkout")
      |> fill_in("Card message", with: "Happy birthday!")
      |> fill_in("Recipient name *", with: "Updated Recipient")
      |> assert_has("[data-testid='card-message-textarea']", text: "Happy birthday!")
    end

    test "addresses the card to the recipient as their name is typed",
         %{conn: conn, variant: variant, card_variant: card_variant} do
      gift_order = generate(order(state: :gift_options, gift: true, recipient_name: "Original"))

      Orders.add_line_item!(gift_order.id, variant.id, 1, authorize?: false)

      Orders.add_card!(gift_order, card_variant.id, authorize?: false, load: [:line_items])

      conn
      |> Plug.Test.init_test_session(%{order_id: gift_order.id})
      |> visit("/checkout")
      |> assert_has("[data-testid='card-message-recipient']", text: "For Original")
      |> fill_in("Recipient name *", with: "Anna Lindqvist")
      |> assert_has("[data-testid='card-message-recipient']", text: "For Anna")
      |> fill_in("Recipient name *", with: "")
      |> assert_has("[data-testid='card-message-recipient'][hidden]")
      |> fill_in("Recipient name *", with: "Bo")
      |> assert_has("[data-testid='card-message-recipient']:not([hidden])", text: "For Bo")
    end

    test "renders maxlength matching the selected card's size limit",
         %{conn: conn, variant: variant, card_variant: card_variant} do
      gift_order = generate(order(state: :gift_options, gift: true, recipient_name: "Test"))

      Orders.add_line_item!(gift_order.id, variant.id, 1, authorize?: false)

      Orders.add_card!(gift_order, card_variant.id, authorize?: false, load: [:line_items])

      {:ok, _view, html} =
        conn
        |> Plug.Test.init_test_session(%{order_id: gift_order.id})
        |> live("/checkout")

      assert html =~ ~s(maxlength="80")
    end

    test "switching from small to large card updates the rendered limit",
         %{conn: conn, variant: variant, card_product: card_product, card_variant: card_variant} do
      large_variant =
        generate(product_variant(product_id: card_product.id, size: :large, draft: false))

      gift_order = generate(order(state: :gift_options, gift: true, recipient_name: "Test"))

      Orders.add_line_item!(gift_order.id, variant.id, 1, authorize?: false)

      Orders.add_card!(gift_order, card_variant.id, authorize?: false, load: [:line_items])

      {:ok, view, html} =
        conn
        |> Plug.Test.init_test_session(%{order_id: gift_order.id})
        |> live("/checkout")

      assert html =~ ~s(maxlength="80")

      html = view |> element("[data-testid='card-option-#{large_variant.id}']") |> render_click()

      assert html =~ ~s(maxlength="200")
    end

    test "card_message is preserved when switching to a different card",
         %{conn: conn, variant: variant, card_product: card_product, card_variant: card_variant} do
      large_variant =
        generate(product_variant(product_id: card_product.id, size: :large, draft: false))

      gift_order = generate(order(state: :gift_options, gift: true, recipient_name: "Test"))

      Orders.add_line_item!(gift_order.id, variant.id, 1, authorize?: false)

      Orders.add_card!(gift_order, card_variant.id, authorize?: false, load: [:line_items])

      conn
      |> Plug.Test.init_test_session(%{order_id: gift_order.id})
      |> visit("/checkout")
      |> fill_in("Card message", with: "Happy birthday!")
      |> assert_has("[data-testid='card-message-textarea']", text: "Happy birthday!")
      |> unwrap(fn view ->
        view |> element("[data-testid='card-option-#{large_variant.id}']") |> render_click()
      end)
      |> assert_has("[data-testid='card-message-textarea']", text: "Happy birthday!")
    end

    test "submitting an oversize message renders the inline error",
         %{conn: conn, variant: variant, card_variant: card_variant} do
      gift_order = generate(order(state: :gift_options, gift: true, recipient_name: "Test"))

      Orders.add_line_item!(gift_order.id, variant.id, 1, authorize?: false)

      Orders.add_card!(gift_order, card_variant.id, authorize?: false, load: [:line_items])

      oversize = String.duplicate("a", 81)

      conn
      |> Plug.Test.init_test_session(%{order_id: gift_order.id})
      |> visit("/checkout")
      |> fill_in("Card message", with: oversize)
      |> click_button("Next")
      |> assert_has("p", text: "at most")
    end

    test "re-adding a card after removal renders an empty card_message field",
         %{conn: conn, variant: variant, card_variant: card_variant} do
      gift_order = generate(order(state: :gift_options, gift: true, recipient_name: "Test"))

      Orders.add_line_item!(gift_order.id, variant.id, 1, authorize?: false)

      card =
        Orders.add_card!(gift_order, card_variant.id, authorize?: false, load: [:line_items]).line_items
        |> Enum.find(& &1.is_card)

      {:ok, view, _html} =
        conn
        |> Plug.Test.init_test_session(%{order_id: gift_order.id})
        |> live("/checkout")

      view
      |> element("[data-testid='checkout-form-2']")
      |> render_change(%{"form" => %{"card_message" => "Stale message"}})

      view |> element("#checkout-line-items-remove-#{card.id}") |> render_click()
      render(view)
      html = view |> element("[data-testid='card-option-#{card_variant.id}']") |> render_click()

      assert html =~ ~r{<textarea[^>]*data-testid="card-message-textarea"[^>]*>\s*</textarea>}
    end
  end

  describe "Submitting a step with errors" do
    test "focuses the first invalid field", %{conn: conn, order: order} do
      {:ok, view, _html} =
        conn
        |> Plug.Test.init_test_session(%{order_id: order.id})
        |> live("/checkout")

      view
      |> element("[data-testid='checkout-form-1']")
      |> render_submit(%{"form" => %{"customer_name" => "", "customer_email" => ""}})

      assert_push_event(view, "focus-first-error", %{})
    end
  end

  describe "Returning to checkout" do
    test "scrolls to the current step without focusing it", %{conn: conn, variant: variant} do
      gift_order = generate(order(state: :gift_options, gift: true))
      Orders.add_line_item!(gift_order.id, variant.id, 1, authorize?: false)

      {:ok, view, _html} =
        conn
        |> Plug.Test.init_test_session(%{order_id: gift_order.id})
        |> live("/checkout")

      assert_push_event(view, "focus-element", %{id: "checkout-section-gift_options", focus: false})
    end

    test "does not scroll on the first step", %{conn: conn, order: order} do
      {:ok, view, _html} =
        conn
        |> Plug.Test.init_test_session(%{order_id: order.id})
        |> live("/checkout")

      refute_push_event(view, "focus-element", %{})
    end
  end

  describe "Step in the URL" do
    test "browser back steps the order back, and a step past it is corrected", %{conn: conn, order: order} do
      {:ok, view, _html} =
        conn
        |> Plug.Test.init_test_session(%{order_id: order.id})
        |> live("/checkout")

      view
      |> element("[data-testid='checkout-form-1']")
      |> render_submit(%{"form" => %{"customer_name" => "Back Button", "customer_email" => "back@example.com"}})

      assert_patch(view, "/checkout?step=gift_options")

      render_patch(view, "/checkout?step=contact_details")
      assert has_element?(view, "[data-testid='checkout-step-1']")
      assert Orders.get_order_by_id!(order.id, authorize?: false).state == :contact_details

      render_patch(view, "/checkout?step=gift_options")
      assert_patch(view, "/checkout?step=contact_details")
      assert has_element?(view, "[data-testid='checkout-step-1']")
      assert Orders.get_order_by_id!(order.id, authorize?: false).state == :contact_details
    end
  end

  describe "Cart-empty reset" do
    setup %{order: order} do
      cards_category = generate(product_category(slug: "cards", visibility: :public))
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
      Orders.add_card!(order, card_variant.id, authorize?: false, load: [:line_items])
      [non_card_line_item] = Enum.reject(order.line_items, & &1.is_card)
      # Bypass Orders.remove_line_item to fabricate the stale state this guard
      # is meant to catch — a card-only cart with leftover checkout fields.
      Ash.destroy!(non_card_line_item, action: :remove_item, authorize?: false)

      stale =
        order
        |> Ash.Changeset.for_update(:submit_contact_details, %{
          customer_name: "Stale Customer",
          customer_email: "stale@example.com"
        })
        |> Ash.update!(authorize?: false)

      conn = Plug.Test.init_test_session(conn, %{order_id: stale.id})

      capture_log(fn ->
        assert {:error, {:live_redirect, %{to: "/en"}}} = live(conn, "/checkout")
      end)

      reloaded = Orders.get_order_for_checkout!(stale.id, actor: nil)
      assert reloaded.line_items == []
      assert is_nil(reloaded.customer_name)
      assert reloaded.state == :contact_details
    end

    test "removing the last non-card line item mid-checkout resets the order and redirects",
         %{conn: conn, order: order, card_variant: card_variant} do
      Orders.add_card!(order, card_variant.id, authorize?: false, load: [:line_items])
      [non_card_line_item] = Enum.reject(order.line_items, & &1.is_card)

      conn = Plug.Test.init_test_session(conn, %{order_id: order.id})
      {:ok, view, _html} = live(conn, "/checkout")

      capture_log(fn ->
        Orders.remove_line_item!(order, non_card_line_item.id, authorize?: false)
        # Destroy, reset and PubSub all run before the redirect; slow under a full suite.
        assert_redirect(view, "/en", 1_000)
      end)

      reloaded = Orders.get_order_for_checkout!(order.id, actor: nil)
      assert reloaded.line_items == []
    end
  end

  describe "Cart with only add-ons" do
    setup do
      chocolate = generate(product(product_category_id: generate(product_category(add_on: true)).id))
      %{chocolate_variant: generate(product_variant(product_id: chocolate.id))}
    end

    test "mounting sends the customer to the store", %{conn: conn, chocolate_variant: chocolate_variant} do
      order = generate(order())
      Orders.add_line_item!(order.id, chocolate_variant.id, 1, authorize?: false)
      conn = Plug.Test.init_test_session(conn, %{order_id: order.id})

      assert {:error, {:live_redirect, %{to: "/en/store"}}} = live(conn, "/checkout")
    end

    test "removing the flowers mid-checkout sends the customer to the store",
         %{conn: conn, order: order, chocolate_variant: chocolate_variant} do
      Orders.add_line_item!(order.id, chocolate_variant.id, 1, authorize?: false)
      [flowers] = order.line_items

      {:ok, view, _html} = live(Plug.Test.init_test_session(conn, %{order_id: order.id}), "/checkout")
      view |> element("#checkout-line-items-remove-#{flowers.id}") |> render_click()

      assert_redirect(view, "/en/store", 1_000)
    end
  end

  describe "Stock that ran out during checkout" do
    setup %{conn: conn, product: product} do
      wreath = generate(product_variant(product_id: product.id, size: :large, stock_quantity: 2))
      order = generate(order(state: :payment, customer_name: "Jane Doe", customer_email: "jane@example.com"))
      line_item = Orders.add_line_item!(order.id, wreath.id, 2, authorize?: false)

      {:ok, view, _html} = live(Plug.Test.init_test_session(conn, %{order_id: order.id}), "/checkout")

      # Someone else buys one while this customer is checking out.
      wreath |> Ash.Changeset.for_update(:update, %{stock_quantity: 1}) |> Ash.update!(authorize?: false)

      %{view: view, line_item: line_item}
    end

    test "paying is refused and names what's short", %{view: view, line_item: line_item} do
      assert view |> element("#checkout-form-4") |> render_submit() =~ "#{line_item.product_name}: Only 1 left."
      refute_push_event(view, "stripe:process_payment", %{})
    end

    test "paying goes ahead once the cart fits the stock", %{view: view, line_item: line_item} do
      Orders.decrement_line_item!(line_item, authorize?: false)

      view |> element("#checkout-form-4") |> render_submit()

      assert_push_event(view, "stripe:process_payment", %{})
    end
  end
end
