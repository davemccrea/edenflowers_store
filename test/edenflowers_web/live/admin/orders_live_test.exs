defmodule EdenflowersWeb.Admin.OrdersLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  alias AshAuthentication.Jwt
  alias AshAuthentication.Plug.Helpers

  setup %{conn: conn} do
    admin = generate(admin_user()) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(admin)

    %{conn: conn}
  end

  test "searches orders by order reference as well as customer name", %{conn: conn} do
    placed_order(order_reference: "ABC123", customer_name: "Ada Lovelace")
    placed_order(order_reference: "XYZ789", customer_name: "Grace Hopper")

    {:ok, view, _html} = live(conn, ~p"/admin/orders?search=abc1")

    assert has_element?(view, "[data-item-id]", "Ada Lovelace")
    refute has_element?(view, "[data-item-id]", "Grace Hopper")

    {:ok, view, _html} = live(conn, ~p"/admin/orders?search=grace")

    assert has_element?(view, "[data-item-id]", "Grace Hopper")
    refute has_element?(view, "[data-item-id]", "Ada Lovelace")
  end

  test "the default path lists only paid orders still to fulfil", %{conn: conn} do
    placed_order(customer_name: "To Make", payment_status: :paid, fulfillment_status: :pending)
    placed_order(customer_name: "Already Done", payment_status: :paid, fulfillment_status: :fulfilled)
    placed_order(customer_name: "Unpaid", payment_status: :pending, fulfillment_status: :pending)

    {:ok, view, _html} = live(conn, EdenflowersWeb.Admin.OrdersLive.default_path())

    assert has_element?(view, "[data-item-id]", "To Make")
    refute has_element?(view, "[data-item-id]", "Already Done")
    refute has_element?(view, "[data-item-id]", "Unpaid")
    assert has_element?(view, ~s(nav a[aria-current="page"]), "Orders")
  end

  defp placed_order(attrs) do
    generate(order([state: :placed, ordered_at: DateTime.utc_now(), locale: "en-GB"] ++ attrs))
  end

  defp with_token(user) do
    {:ok, token, _claims} = Jwt.token_for_user(user)
    %{user | __metadata__: Map.put(user.__metadata__ || %{}, :token, token)}
  end
end
