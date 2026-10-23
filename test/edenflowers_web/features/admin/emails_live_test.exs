defmodule EdenflowersWeb.Admin.EmailsLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  alias AshAuthentication.Plug.Helpers

  defp sign_in(conn, user) do
    conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(with_token(user))
  end

  test "shows every email in the chosen language", %{conn: conn} do
    conn = sign_in(conn, generate(admin_user()))

    {:ok, view, html} = live(conn, ~p"/admin/emails")
    assert html =~ "lördag 14.11.2026"
    assert has_element?(view, "details > summary", "Order receipt")
    assert has_element?(view, "details summary", "not yet fulfilled, cancellable")

    html = view |> element("a", "English") |> render_click()
    assert_patch(view, ~p"/admin/emails?lang=en")
    assert html =~ "Your Eden Flowers order for Saturday 14.11."

    html = view |> element("a", "Suomi") |> render_click()
    assert_patch(view, ~p"/admin/emails?lang=fi")
    assert html =~ "lauantaina 14.11.2026"
    refute html =~ "Your Eden Flowers order for Saturday 14.11."
  end

  test "non-admins cannot open it", %{conn: conn} do
    conn = sign_in(conn, generate(admin_user(admin: false)))

    assert {:error, {:redirect, _}} = live(conn, ~p"/admin/emails")
  end
end
