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

  test "a signed-in user bounced to sign-in by a stale page does not see 'You must sign in'", %{conn: conn} do
    user = Generator.generate(Generator.admin_user()) |> Generator.with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{"phoenix_flash" => %{"error" => "You must sign in to access this page."}})
      |> AshAuthentication.Plug.Helpers.store_in_session(user)
      |> get(~p"/sign-in?return_to=/account")

    assert redirected_to(conn) == ~p"/"

    refute conn |> recycle() |> get(~p"/") |> html_response(200) =~ "You must sign in"
  end
end
