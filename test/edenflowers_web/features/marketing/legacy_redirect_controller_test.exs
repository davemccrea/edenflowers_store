defmodule EdenflowersWeb.Marketing.LegacyRedirectControllerTest do
  use EdenflowersWeb.ConnCase, async: true

  test "old welcome pages move permanently to the home page in their language", %{conn: conn} do
    for {old, home} <- [{"/valkommen", "/sv"}, {"/tervetuloa", "/fi"}] do
      assert conn |> get(old) |> redirected_to(301) == home
    end
  end
end
