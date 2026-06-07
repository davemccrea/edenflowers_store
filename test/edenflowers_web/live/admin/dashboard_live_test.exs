defmodule EdenflowersWeb.Admin.DashboardLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator

  alias AshAuthentication.Jwt
  alias AshAuthentication.Plug.Helpers

  test "renders the current admin account menu using the first-name calculation", %{conn: conn} do
    admin = generate(admin_user(name: "Jane Doe", email: "jane@example.com")) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(admin)

    {:ok, _view, html} = live(conn, ~p"/admin")

    assert html =~ "Admin account menu"
    assert html =~ "Jane"
    assert html =~ "jane@example.com"
    assert html =~ "JD"
    refute html =~ "Jane Doe"
  end

  test "links upcoming order rows to the order detail page", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(admin)

    order =
      generate(
        order(
          state: :placed,
          customer_name: "Ada Lovelace",
          fulfillment_method: :pickup,
          fulfillment_date: ~D[2026-06-10],
          fulfillment_status: :pending,
          grand_total: "42.00",
          ordered_at: DateTime.utc_now()
        )
      )

    {:ok, view, _html} = live(conn, ~p"/admin")

    assert has_element?(view, ~s|a[href="/admin/orders/#{order.id}"]|, "Ada Lovelace")
  end

  defp with_token(user) do
    {:ok, token, _claims} = Jwt.token_for_user(user)
    %{user | __metadata__: Map.put(user.__metadata__ || %{}, :token, token)}
  end
end
