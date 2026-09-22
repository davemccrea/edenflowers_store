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

  defp placed_order(attrs) do
    generate(order([state: :placed, ordered_at: DateTime.utc_now(), locale: "en-GB"] ++ attrs))
  end

  defp with_token(user) do
    {:ok, token, _claims} = Jwt.token_for_user(user)
    %{user | __metadata__: Map.put(user.__metadata__ || %{}, :token, token)}
  end
end
