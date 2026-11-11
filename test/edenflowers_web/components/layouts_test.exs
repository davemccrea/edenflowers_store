defmodule EdenflowersWeb.LayoutsTest do
  # Run synchronously because these tests change the globally shared Umami configuration.
  use EdenflowersWeb.ConnCase, async: false

  import Generator
  import Phoenix.LiveViewTest

  @tracker ~s|data-website-id="site-1"|

  setup do
    Application.put_env(:edenflowers, :umami_website_id, "site-1")
    on_exit(fn -> Application.delete_env(:edenflowers, :umami_website_id) end)
  end

  test "loads the Umami tracker for shoppers", %{conn: conn} do
    html = conn |> get(~p"/en") |> html_response(200)

    assert html =~ @tracker
  end

  test "leaves staff out of Umami, on the shop and the admin", %{conn: conn} do
    conn = log_in(conn, generate(admin_user()) |> with_token())

    refute conn |> get(~p"/en") |> html_response(200) =~ @tracker
    refute conn |> get(~p"/admin") |> html_response(200) =~ @tracker
  end

  test "loads no tracker without a website id", %{conn: conn} do
    Application.delete_env(:edenflowers, :umami_website_id)

    refute conn |> get(~p"/en") |> html_response(200) =~ "data-website-id"
  end

  test "admin menus use live navigation for every admin page", %{conn: conn} do
    conn = log_in(conn, generate(admin_user()) |> with_token())
    html = conn |> get(~p"/admin") |> html_response(200) |> LazyHTML.from_document()

    assert [_, _] = html |> LazyHTML.query(~s|nav a[href="/admin/invoices"]|) |> Enum.to_list()

    for link <- LazyHTML.query(html, "nav a") do
      [href] = LazyHTML.attribute(link, "href")

      if String.starts_with?(href, "/admin") do
        assert LazyHTML.attribute(link, "data-phx-link") == ["redirect"], href
      else
        assert LazyHTML.attribute(link, "data-phx-link") == [], href
        assert LazyHTML.attribute(link, "target") == ["_blank"], href
      end
    end
  end

  test "admin wordmarks return to Overview through live navigation", %{conn: conn} do
    conn = log_in(conn, generate(admin_user()) |> with_token())

    for location <- [~s|[class~="[view-transition-name:admin-topbar]"]|, ".admin-sidebar", "#admin-nav-drawer-dialog"] do
      {:ok, view, _} = live(conn, ~p"/admin/account")

      {:ok, overview, _} =
        view
        |> element(~s|#{location} a.logo-wordmark[href="/admin"][data-phx-link="redirect"]|)
        |> render_click()
        |> follow_redirect(conn, ~p"/admin")

      assert has_element?(overview, "#day-orders-title", "Today")
    end
  end

  test "Invoices opens through live navigation from both admin menus", %{conn: conn} do
    conn = log_in(conn, generate(admin_user()) |> with_token())

    for menu <- [".admin-sidebar", "#admin-nav-drawer-dialog"] do
      {:ok, view, _} = live(conn, ~p"/admin")

      {:ok, invoices, _} =
        view
        |> element(~s|#{menu} nav a[href="/admin/invoices"]|)
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/invoices")

      assert has_element?(invoices, "h1", "Invoices")
      assert has_element?(invoices, ~s|#{menu} nav a[aria-current="page"]|, "Invoices")
      assert has_element?(invoices, ~s|a[href="/admin/invoices/new"][data-phx-link="redirect"]|, "New invoice")
    end
  end
end
