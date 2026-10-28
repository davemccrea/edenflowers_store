defmodule EdenflowersWeb.Admin.LinksLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator

  test "admin sees the links from links.md", %{conn: conn} do
    conn = log_in(conn, generate(admin_user()) |> with_token())

    {:ok, _view, html} = live(conn, ~p"/admin/links")

    assert html =~ ~s(<a href="/admin/oban">)
    assert html =~ ~s(<a href="https://dashboard.stripe.com">)
  end
end
