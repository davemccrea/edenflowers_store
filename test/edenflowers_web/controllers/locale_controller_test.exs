defmodule EdenflowersWeb.LocaleControllerTest do
  use EdenflowersWeb.ConnCase, async: true

  @session_key Localize.Plug.PutLocale.session_key()

  describe "GET /locale/:locale" do
    for locale <- ~w(sv-FI fi en-GB) do
      test "accepts #{locale} and stores it in the session" do
        conn =
          build_conn()
          |> get("/locale/#{unquote(locale)}")

        assert get_session(conn, @session_key) == unquote(locale)
      end
    end

    test "redirects an unsupported locale to / and does not store it" do
      conn =
        build_conn()
        |> get("/locale/de-DE")

      assert redirected_to(conn) == "/sv"
      refute get_session(conn, @session_key) == "de-DE"
    end
  end

  describe "GET /locale/:locale redirect target" do
    test "follows a local path, including its query string and the sign-in page" do
      for path <- ["/sv/shop?page=2&q=a", "/sv/sign-in"] do
        conn = get(build_conn(), "/locale/fi", %{"redirect_to" => path})
        assert redirected_to(conn) == path
      end
    end

    test "falls back to the home page for anything that is not a local path" do
      for target <- ["https://x.example/", "//evil.example", "/\\evil.example", "shop"] do
        conn = get(build_conn(), "/locale/fi", %{"redirect_to" => target})
        assert redirected_to(conn) == "/sv"
      end
    end

    test "applies the same check to the Referer" do
      conn = build_conn() |> put_req_header("referer", "https://shop.example//evil.example") |> get("/locale/fi")
      assert redirected_to(conn) == "/sv"
    end
  end

  describe "GET /admin-locale/:locale" do
    for locale <- ~w(sv-FI en-GB) do
      test "stores #{locale} separately from the storefront preference" do
        conn =
          build_conn()
          |> init_test_session(%{@session_key => "fi"})
          |> get("/admin-locale/#{unquote(locale)}")

        assert redirected_to(conn) == "/admin/account"
        assert get_session(conn, "admin_locale") == unquote(locale)
        assert get_session(conn, @session_key) == "fi"
      end
    end

    test "rejects Finnish and unsupported admin preferences" do
      for locale <- ~w(fi de-DE) do
        conn =
          build_conn()
          |> init_test_session(%{@session_key => "fi", "admin_locale" => "en-GB"})
          |> get("/admin-locale/#{locale}")

        assert get_session(conn, "admin_locale") == "en-GB"
        assert get_session(conn, @session_key) == "fi"
      end
    end
  end

  describe "Accept-Language header resolution" do
    for {header, expected} <- [
          {"sv-FI", "sv-FI"},
          {"fi", "fi"},
          {"en-GB", "en-GB"}
        ] do
      test "Accept-Language: #{header} lands on #{expected}" do
        conn =
          build_conn()
          |> put_req_header("accept-language", unquote(header))
          |> get("/")

        assert get_session(conn, @session_key) == unquote(expected)
      end
    end

    test "an unsupported Accept-Language falls back to English" do
      conn =
        build_conn()
        |> put_req_header("accept-language", "de-DE")
        |> get("/")

      assert get_session(conn, @session_key) == "en-GB"
    end
  end
end
