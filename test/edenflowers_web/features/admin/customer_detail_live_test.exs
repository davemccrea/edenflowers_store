defmodule EdenflowersWeb.Admin.CustomerDetailLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator

  alias Edenflowers.Accounts

  setup :log_in_admin

  test "only reloads a changed customer after explicit reload", %{conn: conn, admin: admin} do
    customer = generate(admin_user(admin: false, name: "Ada Byron", email: "ada@example.com"))
    placed_order(user_id: customer.id, customer_name: "Ada Byron", customer_email: customer.email)

    {:ok, view, _html} = live(conn, ~p"/admin/customers/#{customer.id}")

    assert has_element?(view, "h1", "Ada Byron")

    {:ok, _customer} = Accounts.update_name(customer, "Ada Lovelace", actor: admin)
    assert has_element?(view, "#editor-stale-notice")
    assert has_element?(view, "h1", "Ada Byron")
    view |> element("#editor-stale-notice button") |> render_click()
    {path, _} = assert_redirect(view)
    {:ok, view, _} = live(conn, path)
    assert has_element?(view, "h1", "Ada Lovelace")
  end
end
