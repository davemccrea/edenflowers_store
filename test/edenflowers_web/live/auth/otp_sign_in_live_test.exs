defmodule EdenflowersWeb.Auth.OtpSignInLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "switching language on the code step keeps the email", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/sign-in?#{[email: "a+b@example.com"]}")

    link = view |> element("#locale-picker-footer a[href^='/locale/fi']") |> render()
    [_, locale_href] = Regex.run(~r/href="([^"]+)"/, link)

    conn = get(conn, locale_href)
    {:ok, _view, html} = live(recycle(conn), redirected_to(conn))

    assert html =~ "a+b@example.com"
  end
end
