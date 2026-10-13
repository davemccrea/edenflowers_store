defmodule EdenflowersWeb.Admin.SearchLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator

  alias AshAuthentication.Plug.Helpers

  setup %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    %{conn: conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(admin)}
  end

  test "finds orders and customers from one search", %{conn: conn} do
    customer = generate(admin_user(admin: false, name: "Ada Byron", email: "ada@example.com"))

    order =
      generate(
        order(
          state: :placed,
          customer_name: "Ada Lovelace",
          user_id: customer.id,
          fulfillment_method: :pickup,
          fulfillment_date: ~D[2026-06-10],
          fulfillment_status: :pending,
          grand_total: "42.00",
          ordered_at: DateTime.utc_now()
        )
      )

    generate(admin_user(admin: false, name: "Grace Hopper", email: "grace@example.com"))

    {:ok, view, _html} = live(conn, ~p"/admin/search?q=ada")

    assert has_element?(view, ~s|#search-orders a[href="/admin/orders/#{order.id}"]|, "Ada Lovelace")
    assert has_element?(view, ~s|#search-customers a[href="/admin/customers/#{customer.id}"]|, "Ada Byron")
    refute render(view) =~ "Grace Hopper"
  end

  test "the admin header searches", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin")

    assert html =~ ~s(action="/admin/search")
  end
end
