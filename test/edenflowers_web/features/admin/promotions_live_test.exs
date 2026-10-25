defmodule EdenflowersWeb.Admin.PromotionsLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  setup :log_in_admin

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
