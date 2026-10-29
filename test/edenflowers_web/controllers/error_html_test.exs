defmodule EdenflowersWeb.ErrorHTMLTest do
  use EdenflowersWeb.ConnCase, async: true

  test "an unknown URL shows the branded not found page", %{conn: conn} do
    body = conn |> get("/no-such-page") |> html_response(404)

    assert body =~ "Page not found"
    assert body =~ ~r/<title[^>]*>\s*Page not found\s*\| Eden Flowers<\/title>/
    assert body =~ ~s(href="/en/store")
  end
end
