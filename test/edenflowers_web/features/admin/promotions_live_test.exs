defmodule EdenflowersWeb.Admin.PromotionsLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  setup :log_in_admin

  test "welcome offer changes warn regardless of input and saving stays available", %{conn: conn, admin: admin} do
    {:ok, view, _} = live(conn, ~p"/admin/promotions")
    offer = Edenflowers.Pricing.get_welcome_offer!(actor: admin)
    offer = Ash.update!(offer, %{discount_rate: "0.20"}, action: :update, actor: admin)
    assert has_element?(view, "#editor-stale-notice[role=alert]")

    view |> form("#welcome-offer-form", form: %{discount_rate: "25"}) |> render_change()
    offer = Ash.update!(offer, %{discount_rate: "0.30"}, action: :update, actor: admin)
    assert has_element?(view, "#welcome-offer-form input[value='25']")
    assert has_element?(view, "#editor-stale-notice")

    view |> element("#editor-stale-notice button") |> render_click()
    assert has_element?(view, "#welcome-offer-form input[value='30']")
    refute has_element?(view, "#editor-stale-notice")

    Ash.update!(offer, %{discount_rate: "0.35"}, action: :update, actor: admin)
    assert has_element?(view, "#editor-stale-notice")
    view |> form("#welcome-offer-form", form: %{discount_rate: "25"}) |> render_submit()
    assert Decimal.equal?(Edenflowers.Pricing.get_welcome_offer!(actor: admin).discount_rate, "0.25")
    refute has_element?(view, "#editor-stale-notice")
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

  test "refreshes when a promotion changes elsewhere", %{conn: conn, admin: admin} do
    promotion = generate(promotion(name: "Spring sale", code: "BLOOM10"))

    {:ok, view, _html} = live(conn, ~p"/admin/promotions?search=spring")

    assert has_element?(view, "[data-item-id]", "Spring sale")

    {:ok, _promotion} = Ash.update(promotion, %{name: "Spring sale extended"}, actor: admin)

    eventually(fn -> assert has_element?(view, "[data-item-id]", "Spring sale extended") end)
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
