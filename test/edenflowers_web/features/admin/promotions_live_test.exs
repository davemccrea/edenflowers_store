defmodule EdenflowersWeb.Admin.PromotionsLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  alias AshAuthentication.Plug.Helpers

  setup %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    %{conn: conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(admin)}
  end

  test "searches promotions by name", %{conn: conn} do
    generate(promotion(name: "Spring sale", code: "BLOOM10"))
    generate(promotion(name: "Winter sale", code: "FROST10"))

    {:ok, view, _html} = live(conn, ~p"/admin/promotions?search=spring")

    assert has_element?(view, "[data-item-id]", "Spring sale")
    refute has_element?(view, "[data-item-id]", "Winter sale")
  end

  test "searches promotions by code", %{conn: conn} do
    generate(promotion(name: "Spring sale", code: "BLOOM10"))
    generate(promotion(name: "Winter sale", code: "FROST10"))

    {:ok, view, _html} = live(conn, ~p"/admin/promotions?search=frost")

    assert has_element?(view, "[data-item-id]", "Winter sale")
    refute has_element?(view, "[data-item-id]", "Spring sale")
  end
end
