defmodule EdenflowersWeb.Checkout.PayLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Mox
  import Phoenix.LiveViewTest

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders

  setup :verify_on_exit!

  setup do
    admin = generate(admin_user())
    tax_rate = generate(tax_rate())
    pickup = generate(fulfillment_option(tax_rate_id: tax_rate.id, base_price: "0.00"))

    {:ok, order} =
      Orders.place_custom_order(
        %{
          customer_name: "Anna Holm",
          customer_email: "anna@example.com",
          fulfillment_option_id: pickup.id,
          fulfillment_date: Date.add(Edenflowers.ShopTime.today(), 1),
          locale: "en-GB",
          florist_note: "Customer is particular about lilies",
          email_customer?: false,
          line_items: [
            %{
              "kind" => "custom",
              "product_name" => "Funeral spray",
              "unit_price" => "85.00",
              "tax_rate_id" => tax_rate.id,
              "quantity" => "1"
            }
          ]
        },
        actor: admin
      )

    %{admin: admin, order: order}
  end

  test "shows the order and a payment form for its total", %{conn: conn, order: order} do
    {:ok, view, _html} = live(conn, ~p"/pay/#{order.payment_link_token}")

    assert has_element?(view, "h1", "Pay for order")
    assert has_element?(view, "dl", "Funeral spray")
    assert has_element?(view, "[data-testid=pay-total]", "85.00")
    refute has_element?(view, "[data-testid=pay-balance]")
    refute render(view) =~ "Paid so far"
    assert has_element?(view, ~s|#pay-form[data-amount="8500"]|)
    refute render(view) =~ "lilies"
  end

  test "creates the PaymentIntent when the customer pays", %{conn: conn, order: order} do
    order_id = order.id

    expect(StripeAPI.Mock, :create_payment_intent, fn 8500, %{"order_id" => ^order_id}, _customer ->
      {:ok, %{id: "pi_link", client_secret: "pi_link_secret", amount: 8500}}
    end)

    {:ok, view, _html} = live(conn, ~p"/pay/#{order.payment_link_token}")
    view |> element("#pay-form") |> render_submit()

    assert_push_event(view, "stripe:process_payment", %{client_secret: "pi_link_secret"})
  end

  test "brings an earlier PaymentIntent up to the total when the customer pays again", %{
    conn: conn,
    order: order
  } do
    order = Ash.Seed.update!(order, %{payment_intent_id: "pi_link"})

    expect(StripeAPI.Mock, :update_payment_intent, fn "pi_link", 8500 -> {:ok, %{id: "pi_link"}} end)
    expect(StripeAPI.Mock, :retrieve_payment_intent, fn _order -> {:ok, %{client_secret: "pi_link_secret"}} end)

    {:ok, view, _html} = live(conn, ~p"/pay/#{order.payment_link_token}")
    view |> element("#pay-form") |> render_submit()

    assert_push_event(view, "stripe:process_payment", %{client_secret: "pi_link_secret"})
  end

  test "reloads instead of paying when the order changed since the page was shown", %{conn: conn, order: order} do
    {:ok, view, _html} = live(conn, ~p"/pay/#{order.payment_link_token}")
    Ash.Seed.update!(order, %{quoted_fulfillment_fee: Decimal.new("10.00")})

    {:ok, _view, html} =
      view
      |> element("#pay-form")
      |> render_submit()
      |> follow_redirect(conn, ~p"/pay/#{order.payment_link_token}")

    assert html =~ "The order changed. Please try again."
  end

  @tag capture_log: true
  test "keeps the form when Stripe is down", %{conn: conn, order: order} do
    expect(StripeAPI.Mock, :create_payment_intent, fn _amount, _metadata, _customer -> {:error, :stripe_down} end)

    {:ok, view, _html} = live(conn, ~p"/pay/#{order.payment_link_token}")

    assert view |> element("#pay-form") |> render_submit() =~ "Payment is temporarily unavailable"
    assert_push_event(view, "stripe:ready", %{})
  end

  test "asks for an email when the order has none, and links the order to that customer", %{
    conn: conn,
    order: order
  } do
    order = Ash.Seed.update!(order, %{customer_email: nil, user_id: nil, payment_intent_id: "pi_link"})

    expect(StripeAPI.Mock, :update_payment_intent, fn "pi_link", 8500 -> {:ok, %{id: "pi_link"}} end)
    expect(StripeAPI.Mock, :retrieve_payment_intent, fn _order -> {:ok, %{client_secret: "pi_link_secret"}} end)

    {:ok, view, _html} = live(conn, ~p"/pay/#{order.payment_link_token}")

    view |> form("#pay-form", %{form: %{customer_email: " anna@example.com "}}) |> render_submit()

    assert_push_event(view, "stripe:process_payment", %{})
    refute has_element?(view, ~s|input[name="form[customer_email]"]|)
    assert has_element?(view, ~s|#pay-form[data-billing-email="anna@example.com"]|)

    order = Ash.get!(Orders.Order, order.id, authorize?: false)
    assert to_string(order.customer_email) == "anna@example.com"
    assert order.user_id
  end

  test "shows an invalid email under the field, as checkout does, and doesn't pay", %{conn: conn, order: order} do
    order = Ash.Seed.update!(order, %{customer_email: nil, user_id: nil})

    {:ok, view, _html} = live(conn, ~p"/pay/#{order.payment_link_token}")

    view |> form("#pay-form", %{form: %{customer_email: "anna@example"}}) |> render_change()
    assert has_element?(view, "#pay-form", "Must be a valid email address")

    view |> form("#pay-form", %{form: %{customer_email: "anna@example"}}) |> render_submit()
    assert has_element?(view, "#pay-form", "Must be a valid email address")
    refute_push_event(view, "stripe:process_payment", %{})
    assert is_nil(Ash.get!(Orders.Order, order.id, authorize?: false).customer_email)
  end

  test "doesn't ask for an email the order already has", %{conn: conn, order: order} do
    {:ok, view, _html} = live(conn, ~p"/pay/#{order.payment_link_token}")

    refute has_element?(view, ~s|input[name="form[customer_email]"]|)
    assert {:error, _} = Orders.add_customer_email(order, "someone@example.com", authorize?: false)
  end

  test "says so once the order is paid", %{conn: conn, admin: admin, order: order} do
    {:ok, _order} =
      Orders.record_payment(order, "85.00", :cash, actor: admin)

    {:ok, view, _html} = live(conn, ~p"/pay/#{order.payment_link_token}")

    assert has_element?(view, "[data-testid=pay-paid]")
    refute has_element?(view, "#pay-form")
  end

  test "says the order was collected once it's fulfilled", %{conn: conn, order: order} do
    Ash.Seed.update!(order, %{fulfillment_status: :fulfilled})

    {:ok, view, _html} = live(conn, ~p"/pay/#{order.payment_link_token}")

    assert has_element?(
             view,
             "[data-testid=pay-fulfillment]",
             "Your order has been collected. I hope you're happy with it."
           )

    refute has_element?(view, "[data-testid=pay-fulfillment]", "Ready to collect")
  end

  test "says so once the order is refunded", %{conn: conn, order: order} do
    generate(payment(order_id: order.id, amount: "85.00"))
    generate(payment(order_id: order.id, amount: "-85.00"))

    {:ok, view, _html} = live(conn, ~p"/pay/#{order.payment_link_token}")

    assert has_element?(view, "[data-testid=pay-refunded]")
    refute has_element?(view, "[data-testid=pay-paid]")
    refute has_element?(view, "#pay-form")
  end

  test "says so once the order is cancelled", %{conn: conn, admin: admin, order: order} do
    {:ok, _order} = Orders.cancel_order(order, actor: admin)

    {:ok, view, _html} = live(conn, ~p"/pay/#{order.payment_link_token}")

    assert has_element?(view, "[data-testid=pay-cancelled]")
    refute has_element?(view, "[data-testid=pay-fulfillment]")
    refute has_element?(view, "#pay-form")
  end

  test "rejects a link that doesn't match an order", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/en"}}} = live(conn, ~p"/pay/not-a-token")
  end

  test "updates when the payment arrives while the customer waits", %{conn: conn, order: order} do
    order = Ash.Seed.update!(order, %{payment_intent_id: "pi_link"})

    {:ok, view, _html} = live(conn, ~p"/pay/#{order.payment_link_token}?redirect_status=succeeded")

    assert has_element?(view, "[data-testid=pay-confirming]")

    {:ok, :completed} =
      Edenflowers.Payments.complete(%{id: "pi_link", metadata: %{"order_id" => order.id}, amount_received: 8500})

    assert has_element?(view, "[data-testid=pay-paid]")
  end
end
