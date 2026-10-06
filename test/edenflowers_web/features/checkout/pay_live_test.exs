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
          fulfillment_date: Date.add(DateTime.now!("Europe/Helsinki") |> DateTime.to_date(), 1),
          locale: "en-GB",
          florist_note: "Customer is particular about lilies",
          email_customer?: false,
          line_items: [
            %{
              "kind" => "custom",
              "description" => "Funeral spray",
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
    order_id = order.id

    expect(StripeAPI.Mock, :create_payment_intent, fn 8500, %{"order_id" => ^order_id} ->
      {:ok, %{id: "pi_link", client_secret: "pi_link_secret", amount: 8500}}
    end)

    {:ok, view, _html} = live(conn, ~p"/pay/#{order.payment_link_token}")

    assert has_element?(view, "h1", "Pay for your order")
    assert has_element?(view, "dl", "Funeral spray")
    assert has_element?(view, "[data-testid=pay-total]", "85.00")
    assert has_element?(view, ~s|#pay-form[data-client-secret="pi_link_secret"]|)
    refute render(view) =~ "lilies"
  end

  test "charges the current total when the order changed since the payment form was made", %{
    conn: conn,
    order: order
  } do
    order = Ash.Seed.update!(order, %{payment_intent_id: "pi_link"})

    expect(StripeAPI.Mock, :update_payment_intent, fn "pi_link", 8500 -> {:ok, %{id: "pi_link"}} end)

    expect(StripeAPI.Mock, :retrieve_payment_intent, fn _order -> {:ok, %{client_secret: "pi_link_secret"}} end)

    {:ok, view, _html} = live(conn, ~p"/pay/#{order.payment_link_token}")

    assert has_element?(view, "#pay-form")
  end

  test "says so once the order is paid", %{conn: conn, admin: admin, order: order} do
    {:ok, _order} =
      Orders.record_in_person_payment(order, "85.00", :cash, actor: admin)

    {:ok, view, _html} = live(conn, ~p"/pay/#{order.payment_link_token}")

    assert has_element?(view, "[data-testid=pay-paid]")
    refute has_element?(view, "#pay-form")
  end

  test "says so once the order is cancelled", %{conn: conn, admin: admin, order: order} do
    {:ok, _order} = Orders.cancel_order(order, actor: admin)

    {:ok, view, _html} = live(conn, ~p"/pay/#{order.payment_link_token}")

    assert has_element?(view, "[data-testid=pay-cancelled]")
    refute has_element?(view, "#pay-form")
  end

  test "rejects a link that doesn't match an order", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/pay/not-a-token")
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
