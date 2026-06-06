defmodule EdenflowersWeb.Admin.OrderDetailLiveTest do
  use EdenflowersWeb.ConnCase, async: false

  import Generator
  import Phoenix.LiveViewTest

  alias AshAuthentication.Jwt
  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.Store.Order

  setup %{conn: conn} do
    admin = generate(admin_user()) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(admin)

    %{conn: conn, admin: admin}
  end

  test "renders a placed order detail page", %{conn: conn} do
    order = placed_order()

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, "h1", "Ada Lovelace")
    assert has_element?(view, "header", order.order_reference)
    assert has_element?(view, "header", "Payment")
    assert has_element?(view, "header", "Fulfillment")
    assert has_element?(view, "#order-fulfillment-summary", "Pickup")
    assert has_element?(view, "#order-fulfillment-summary", "2026")
    assert has_element?(view, "#order-payment-summary", "View payment in Stripe")
    refute has_element?(view, "#order-technical-details")
    assert has_element?(view, ~s|button[phx-click="mark_fulfilled"]|)
  end

  test "marking an order fulfilled flips the status and shows the fulfilled badge", %{conn: conn} do
    order = placed_order()

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    view
    |> element(~s|button[phx-click="mark_fulfilled"]|)
    |> render_click()

    refute has_element?(view, ~s|button[phx-click="mark_fulfilled"]|)
    assert has_element?(view, ".badge-success", "fulfilled")

    reloaded = Order.get_for_admin!(order.id, actor: %{admin: true})
    assert reloaded.fulfillment_status == :fulfilled
  end

  test "shows recipient gift context and fulfillment option in the operational summary", %{conn: conn} do
    order = placed_order(gift: true, recipient_name: "Grace Hopper")

    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")

    assert has_element?(view, "#order-fulfillment-summary", "Grace Hopper")
    assert has_element?(view, "#order-fulfillment-summary", "Gift")
    assert has_element?(view, "#order-fulfillment-summary", "Pickup")
  end

  test "redirects missing orders back to the admin orders table", %{conn: conn} do
    missing_id = Ash.UUID.generate()

    assert {:error, {:live_redirect, %{to: "/admin/orders"}}} = live(conn, ~p"/admin/orders/#{missing_id}")
  end

  defp placed_order(overrides \\ []) do
    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    variant = generate(product_variant(product_id: product.id, price: "42.00"))
    fulfillment = generate(fulfillment_option(tax_rate_id: tax_rate.id, name: "Pickup"))

    attrs =
      Keyword.merge(
        [
          state: :placed,
          order_reference: "EF-DETAIL",
          customer_name: "Ada Lovelace",
          customer_email: "ada@example.com",
          fulfillment_option_id: fulfillment.id,
          fulfillment_option_name: "Pickup",
          fulfillment_method: :pickup,
          fulfillment_date: ~D[2026-06-10],
          fulfillment_fee: "4.50",
          fulfillment_tax_percentage: tax_rate.percentage,
          payment_status: :paid,
          fulfillment_status: :pending,
          payment_intent_id: "pi_test_order_detail",
          ordered_at: DateTime.utc_now(),
          locale: "en-GB"
        ],
        overrides
      )

    order = generate(order(attrs))

    generate(line_item(order_id: order.id, product_variant_id: variant.id, quantity: 2))
    order
  end

  defp with_token(user) do
    {:ok, token, _claims} = Jwt.token_for_user(user)
    %{user | __metadata__: Map.put(user.__metadata__ || %{}, :token, token)}
  end
end
