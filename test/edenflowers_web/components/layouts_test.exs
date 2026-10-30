defmodule EdenflowersWeb.LayoutsTest do
  # Changes the app's Umami config.
  use EdenflowersWeb.ConnCase, async: false

  import Generator

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
end
