defmodule EdenflowersWeb.LocaleControllerTest do
  use EdenflowersWeb.ConnCase, async: true

  describe "validate_locale/2" do
    for locale <- ~w(sv-FI fi en-GB) do
      test "accepts #{locale}" do
        conn =
          build_conn()
          |> get("/cldr_locale/#{unquote(locale)}")

        assert get_session(conn, "cldr_locale") == unquote(locale)
      end
    end
  end

  describe "accept-language matching" do
    for {header, expected_cldr_locale} <- [
          {"sv-FI", "sv-FI"},
          {"sv-SE", "sv"},
          {"fi", "fi"},
          {"en-GB", "en-GB"},
          {"en-US", "en"}
        ] do
      test "Accept-Language: #{header} resolves to #{expected_cldr_locale}" do
        {:ok, locale} = Localize.validate_locale(unquote(header))
        assert to_string(locale.cldr_locale_id) == unquote(expected_cldr_locale)
      end
    end
  end
end
