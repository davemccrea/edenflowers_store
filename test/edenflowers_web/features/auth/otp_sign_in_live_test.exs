defmodule EdenflowersWeb.Auth.OtpSignInLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "switching language on the code step keeps the email", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/sign-in?#{[email: "a+b@example.com"]}")

    link = view |> element("#locale-picker-footer option[value^='/locale/fi']") |> render()
    [_, locale_href] = Regex.run(~r/value="([^"]+)"/, link)

    conn = get(conn, locale_href)
    {:ok, _view, html} = live(recycle(conn), redirected_to(conn))

    assert html =~ "a+b@example.com"
  end

  test "a signed-in user bounced to sign-in by a stale page does not see 'You must sign in'", %{conn: conn} do
    user = Generator.generate(Generator.admin_user()) |> Generator.with_token()

    conn =
      conn
      |> log_in(user, %{"phoenix_flash" => %{"error" => "You must sign in to access this page."}})
      |> get(~p"/sign-in?return_to=/account")

    assert redirected_to(conn) == ~p"/en"

    refute conn |> recycle() |> get(~p"/en") |> html_response(200) =~ "You must sign in"
  end

  test "a malformed email asks again instead of waiting on a code", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/sign-in")

    html = view |> form("#otp-request", %{"user" => %{"email" => "not an email"}}) |> render_submit()

    assert html =~ "Must be a valid email address"
    refute html =~ "Check your email"
    refute html =~ "We couldn&#39;t send your sign-in code"
  end
end
