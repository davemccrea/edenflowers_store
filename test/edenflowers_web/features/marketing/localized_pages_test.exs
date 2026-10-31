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

  test "a page links to its other languages", %{conn: conn} do
    generate(bouquets())
    html = conn |> get("/sv/butik/bouquets") |> html_response(200)

    assert html =~ ~s(<link rel="alternate" hreflang="en" href="http://localhost:4002/en/store/bouquets")
    assert html =~ ~s(<link rel="alternate" hreflang="fi" href="http://localhost:4002/fi/kauppa/bouquets")
    assert html =~ ~s(<link rel="alternate" hreflang="sv" href="http://localhost:4002/sv/butik/bouquets")
    assert html =~ ~s(<link rel="alternate" hreflang="x-default" href="http://localhost:4002/")
  end

  test "the language switcher goes to the same page in the other language", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/en/about")

    assert has_element?(view, ~s|#locale-picker-footer option[value="/fi/tietoa"]|)
    assert has_element?(view, ~s|#locale-picker-footer option[value="/sv/om"]|)
  end

  test "pages that aren't localized switch language through the session", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/sign-in")

    assert has_element?(view, ~s|#locale-picker-footer option[value="/locale/fi?redirect_to=%2Fsign-in"]|)
  end

  test "information sidebars link to the other two pages in the current language", %{conn: conn} do
    for {faq, terms, privacy} <- [
          {"/en/faq", "/en/terms", "/en/privacy"},
          {"/sv/vanliga-fragor", "/sv/kopvillkor", "/sv/privacy"},
          {"/fi/ukk", "/fi/toimitusehdot", "/fi/privacy"}
        ],
        {path, id, related} <- [
          {faq, "faq-nav", [terms, privacy]},
          {terms, "terms-nav", [faq, privacy]},
          {privacy, "privacy-nav", [faq, terms]}
        ] do
      {:ok, view, html} = live(conn, path)
      document = LazyHTML.from_document(html)

      assert document |> LazyHTML.query("##{id}-related a") |> LazyHTML.attribute("href") == related

      refute has_element?(view, ~s|##{id}-related a[href="#{path}"]|)
    end
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

  describe "a shared link without a language" do
    test "goes to the page in the browser's language, keeping tracking tags", %{conn: conn} do
      id = Ecto.UUID.generate()
      conn = put_req_header(conn, "accept-language", "fi-FI")

      assert conn |> get("/product/#{id}?utm_source=instagram") |> redirected_to(302) ==
               "/fi/tuote/#{id}?utm_source=instagram"

      assert conn |> get("/courses/#{id}") |> redirected_to(302) == "/fi/kurssit/#{id}"
      assert conn |> get("/courses") |> redirected_to(302) == "/fi/kurssit"
      assert conn |> get("/weddings") |> redirected_to(302) == "/fi/haat"
    end
  end

  defp bouquets do
    product_category(
      slug: "bouquets",
      visibility: :public,
      translations: %{fi: %{name: "Kukkakimput"}, "sv-FI": %{name: "Buketter"}}
    )
  end
end
