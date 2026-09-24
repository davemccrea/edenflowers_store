defmodule EdenflowersWeb.Marketing.AdminShortcutTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator

  alias AshAuthentication.Plug.Helpers

  test "shows the admin shortcut to admins", %{conn: conn} do
    {:ok, view, _html} = live(sign_in(conn, generate(admin_user())), ~p"/")

    assert has_element?(view, "#admin-shortcut[href='/admin']")
  end

  test "hides the admin shortcut from customers", %{conn: conn} do
    {:ok, view, _html} = live(sign_in(conn, generate(admin_user(admin: false))), ~p"/")

    refute has_element?(view, "#admin-shortcut")
  end

  defp sign_in(conn, user) do
    user = with_token(user)

    conn
    |> Plug.Test.init_test_session(%{})
    |> Helpers.store_in_session(user)
  end
end
