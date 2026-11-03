defmodule EdenflowersWeb.Marketing.LegacyRedirectControllerTest do
  use EdenflowersWeb.ConnCase, async: true

  test "old welcome pages move permanently to the home page in their language", %{conn: conn} do
    for {old, home} <- [{"/valkommen", "/sv"}, {"/tervetuloa", "/fi"}] do
      assert conn |> get(old) |> redirected_to(301) == home
    end
  end

  test "the privacy policy's untranslated URLs move to the translated ones", %{conn: conn} do
    for {old, new} <- [{"/sv/privacy", "/sv/integritetspolicy"}, {"/fi/privacy", "/fi/tietosuojaseloste"}] do
      assert conn |> get(old) |> redirected_to(301) == new
    end
  end
end
