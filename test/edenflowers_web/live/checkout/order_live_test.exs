defmodule EdenflowersWeb.Checkout.OrderLiveTest do
  use EdenflowersWeb.ConnCase, async: false

  import Generator
  import Phoenix.LiveViewTest

  alias AshAuthentication.Jwt
  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.Orders

  setup %{conn: conn} do
    user = generate(admin_user(admin: false)) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(user)

    %{conn: conn, user: user}
  end

  test "shows a placed order to its owner", %{conn: conn, user: user} do
    order = placed_order(user_id: user.id)

    {:ok, view, _html} = live(conn, ~p"/order/#{order.id}")

    assert has_element?(view, "h1", "EF-CONFIRM")
    assert has_element?(view, "[data-testid=order-summary]", "Total")
    assert has_element?(view, ~s|a[href="/order/#{order.id}/receipt"]|)
  end

  test "hides another customer's order", %{conn: conn} do
    other = generate(admin_user(admin: false))
    order = placed_order(user_id: other.id)

    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/order/#{order.id}")
    assert conn |> get(~p"/order/#{order.id}/receipt") |> response(404)
  end

  test "waits for the webhook, then shows the order", %{conn: conn, user: user} do
    order = placed_order(user_id: user.id, state: :payment, ordered_at: nil)

    {:ok, view, _html} = live(conn, ~p"/order/#{order.id}")
    assert has_element?(view, "[data-testid=order-pending]")

    Orders.finalize_checkout!(order, actor: Edenflowers.Actors.system_actor())

    assert render(view) =~ "EF-CONFIRM"
  end

  @tag :typst
  test "downloads the receipt PDF", %{conn: conn, user: user} do
    order = placed_order(user_id: user.id)

    conn = get(conn, ~p"/order/#{order.id}/receipt")

    assert "%PDF" <> _ = response(conn, 200)
    assert get_resp_header(conn, "content-disposition") == [~s|attachment; filename="eden-flowers-EF-CONFIRM.pdf"|]
  end

  describe "guest" do
    setup do
      %{conn: Phoenix.ConnTest.build_conn() |> Plug.Test.init_test_session(%{})}
    end

    test "sees the order they just paid for", %{conn: conn} do
      order = placed_order([])

      conn = get(conn, ~p"/checkout/complete/#{order.id}?payment_intent=pi_test_confirm")
      assert redirected_to(conn) == ~p"/order/#{order.id}"

      {:ok, view, _html} = live(conn, ~p"/order/#{order.id}")
      assert has_element?(view, "h1", "EF-CONFIRM")
    end

    test "is sent to sign in without the matching payment intent", %{conn: conn} do
      order = placed_order([])

      conn = get(conn, ~p"/checkout/complete/#{order.id}?payment_intent=pi_wrong")

      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/order/#{order.id}")
      assert to =~ "/sign-in?return_to="
      assert conn |> get(~p"/order/#{order.id}/receipt") |> response(404)
    end
  end

  defp placed_order(overrides) do
    tax_rate = generate(tax_rate())
    product = generate(product(tax_rate_id: tax_rate.id))
    variant = generate(product_variant(product_id: product.id, price: "42.00"))
    fulfillment = generate(fulfillment_option(tax_rate_id: tax_rate.id, name: "Pickup"))

    attrs =
      Keyword.merge(
        [
          state: :placed,
          order_reference: "EF-CONFIRM",
          customer_name: "Ada Lovelace",
          customer_email: "ada@example.com",
          fulfillment_option_id: fulfillment.id,
          fulfillment_option_name: "Pickup",
          fulfillment_method: :pickup,
          fulfillment_date: ~D[2026-06-10],
          fulfillment_fee: "4.50",
          fulfillment_tax_percentage: tax_rate.percentage,
          payment_status: :paid,
          payment_intent_id: "pi_test_confirm",
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
