defmodule EdenflowersWeb.Admin.SubscriptionDetailLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  alias AshAuthentication.Plug.Helpers

  setup %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    conn = conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(admin)
    {:ok, customer} = Edenflowers.Accounts.upsert_user("ada@example.com", "Ada Lovelace", authorize?: false)

    %{conn: conn, customer: customer}
  end

  test "shows what Jennie needs to service the subscription", %{conn: conn, customer: customer} do
    large = generate(product_variant(product_id: generate(product()).id, size: :large))

    subscription =
      generate(
        subscription(
          user_id: customer.id,
          product_variant_id: large.id,
          recipient_name: "Grace Hopper",
          delivery_address: "Storgatan 1, Jakobstad",
          delivery_instructions: "Ring the bell twice",
          card_message: "Happy Mondays",
          card_brand: "visa",
          card_last4: "4242",
          card_exp_month: 8,
          card_exp_year: 2027
        )
      )

    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions/#{subscription.id}")

    assert has_element?(view, "h1", "Ada Lovelace")
    assert has_element?(view, "#subscription-customer", "ada@example.com")
    assert has_element?(view, "#subscription-customer-link[href='/admin/customers/#{customer.id}']")
    assert render(view) =~ "Large"
    assert render(view) =~ "Every 2 weeks"
    assert has_element?(view, "#subscription-fulfillment", "Storgatan 1, Jakobstad")
    assert has_element?(view, "#subscription-fulfillment", "Ring the bell twice")
    assert has_element?(view, "#subscription-fulfillment", "Happy Mondays")
    assert has_element?(view, "#subscription-recipient", "Grace Hopper")
    assert has_element?(view, ~s|#subscription-card img[alt="Visa"]|)
    assert has_element?(view, "#subscription-card", "•••• 4242, expires 08/27")
  end

  test "Jennie can pause, resume and cancel, even inside the customer's cutoff", %{conn: conn, customer: customer} do
    next_date = "Europe/Helsinki" |> DateTime.now!() |> DateTime.to_date() |> Date.add(4)
    subscription = generate(subscription(user_id: customer.id, next_fulfillment_date: next_date))

    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions/#{subscription.id}")

    view |> element("button", "Pause") |> render_click()
    assert reload(subscription).state == :paused

    view |> element("button", "Resume") |> render_click()
    assert reload(subscription).state == :active

    view |> element("button", "Cancel") |> render_click()
    assert reload(subscription).state == :cancelled
    refute has_element?(view, "button", "Cancel")
  end

  test "logs who changed the subscription, naming no one for automatic changes", %{conn: conn, customer: customer} do
    product = generate(product())
    medium = generate(product_variant(product_id: product.id, size: :medium, draft: false))
    large = generate(product_variant(product_id: product.id, size: :large, draft: false))

    subscription =
      generate(subscription(user_id: customer.id, product_variant_id: medium.id, state: :payment_failed))

    {:ok, subscription} =
      Edenflowers.Orders.reactivate_subscription(subscription, actor: Edenflowers.Actors.system_actor())

    {:ok, _subscription} =
      Edenflowers.Orders.change_subscription(subscription, %{product_variant_id: large.id}, actor: customer)

    {:ok, view, _html} = live(conn, ~p"/admin/subscriptions/#{subscription.id}")
    view |> element("button", "Pause") |> render_click()

    assert has_element?(view, "#subscription-log li:nth-child(1)", "Paused · Admin")
    assert has_element?(view, "#subscription-log li:nth-child(2)", "Changed · Ada Lovelace")
    assert has_element?(view, "#subscription-log li:nth-child(2)", "Large")
    assert has_element?(view, "#subscription-log li:nth-child(3)", "Payment received, deliveries restarted")
    refute has_element?(view, "#subscription-log li:nth-child(3)", "·")
  end

  defp reload(subscription), do: Ash.reload!(subscription, authorize?: false)
end
