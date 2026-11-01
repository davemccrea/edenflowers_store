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

  test "sets the welcome offer new subscribers' codes are generated with", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/promotions")

    assert has_element?(view, "#welcome-offer-form input[value='15']")

    view
    |> form("#welcome-offer-form", form: %{discount_rate: "25"})
    |> render_submit()

    assert Decimal.equal?(Edenflowers.Pricing.get_welcome_offer!().discount_rate, "0.25")
    assert has_element?(view, "#welcome-offer-form input[value='25']")
  end
end
