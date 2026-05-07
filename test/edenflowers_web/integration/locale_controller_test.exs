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

      assert redirected_to(conn) == "/"
      refute get_session(conn, @session_key) == "de-DE"
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

    test "unsupported Accept-Language falls back to default" do
      conn =
        build_conn()
        |> put_req_header("accept-language", "de-DE")
        |> get("/")

      assert get_session(conn, @session_key) == Edenflowers.Locales.default()
    end
  end
end
