defmodule EdenflowersWeb.Marketing.LocalizedPagesTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  test "a page renders in its URL's language whatever the visitor prefers", %{conn: conn} do
    html = conn |> get("/fi/haat") |> html_response(200)

    assert html =~ ~s(<html lang="fi")
    assert html =~ ~s(<link rel="canonical" href="http://localhost:4002/fi/haat")
    assert get_session(conn |> get("/fi/haat"), Localize.Plug.PutLocale.session_key()) == "fi"
  end

  test "a page links to its other languages, with the category's slug in each", %{conn: conn} do
    generate(bouquets())
    html = conn |> get("/sv/butik/buketter") |> html_response(200)

    assert html =~ ~s(<link rel="alternate" hreflang="en" href="http://localhost:4002/en/store/bouquets")
    assert html =~ ~s(<link rel="alternate" hreflang="fi" href="http://localhost:4002/fi/kauppa/kukkakimput")
    assert html =~ ~s(<link rel="alternate" hreflang="sv" href="http://localhost:4002/sv/butik/buketter")
    assert html =~ ~s(<link rel="alternate" hreflang="x-default" href="http://localhost:4002/")
  end

  test "a category's own-language slug is the only one its URL takes", %{conn: conn} do
    generate(bouquets())

    assert conn |> get("/fi/kauppa/kukkakimput") |> html_response(200) =~ "<h1"
    {:error, {:live_redirect, %{to: "/fi/kauppa/kukkakimput"}}} = live(conn, "/fi/kauppa/buketter")
  end

  test "the language switcher goes to the same page in the other language", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/en/about")

    assert has_element?(view, ~s|#locale-picker-footer option[value="/fi/tietoa"]|)
    assert has_element?(view, ~s|#locale-picker-footer option[value="/sv/om"]|)
  end

  test "customer pages have a URL per language but stay out of search engines", %{conn: conn} do
    user = generate(admin_user(admin: false)) |> with_token()
    conn = conn |> Plug.Test.init_test_session(%{}) |> AshAuthentication.Plug.Helpers.store_in_session(user)
    html = conn |> get("/sv/konto") |> html_response(200)

    assert html =~ ~s(<html lang="sv)
    assert html =~ ~s(<meta name="robots" content="noindex">)
    refute html =~ ~s(rel="canonical")
    refute html =~ ~s(hreflang=)

    {:ok, view, _html} = live(conn, "/sv/konto")
    assert has_element?(view, ~s|#locale-picker-footer option[value="/fi/tili"]|)
  end

  test "pages that aren't localized switch language through the session", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/sign-in")

    assert has_element?(view, ~s|#locale-picker-footer option[value="/locale/fi?redirect_to=%2Fsign-in"]|)
  end

  describe "the bare URL" do
    test "goes to the session's language", %{conn: conn} do
      conn = conn |> get("/fi") |> recycle() |> get("/")

      assert redirected_to(conn, 302) == "/fi"
      assert get_resp_header(conn, "vary") == ["accept-language, cookie"]
    end

    test "goes to the browser's language without a session", %{conn: conn} do
      conn = conn |> put_req_header("accept-language", "fi-FI") |> get("/")

      assert redirected_to(conn, 302) == "/fi"
    end

    test "goes to Swedish without a preference" do
      assert build_conn() |> get("/") |> redirected_to(302) == "/sv"
    end
  end

  defp bouquets do
    product_category(
      slug: "bouquets",
      visibility: :public,
      translations: %{fi: %{name: "Kukkakimput", slug: "kukkakimput"}, "sv-FI": %{name: "Buketter", slug: "buketter"}}
    )
  end
end
