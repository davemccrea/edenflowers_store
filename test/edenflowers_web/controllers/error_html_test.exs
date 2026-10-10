defmodule EdenflowersWeb.ErrorHTMLTest do
  use EdenflowersWeb.ConnCase, async: true

  test "an unknown URL shows the branded not found page", %{conn: conn} do
    body = conn |> get("/no-such-page") |> html_response(404)

    assert body =~ "Page not found"
    assert body =~ ~s(href="/store")
    assert body =~ "app.css"
  end
end
