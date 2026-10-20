defmodule EdenflowersWeb.Marketing.HomeLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator

  test "the hero quotes the cheapest bouquet, not a cheaper product in another category", %{conn: conn} do
    bouquets = generate(product_category(slug: "bouquets", visibility: :public))
    plants = generate(product_category(visibility: :public))

    bouquet = generate(product(product_category_id: bouquets.id, draft: false))
    generate(product_variant(product_id: bouquet.id, price: "42.00", draft: false))
    generate(product_variant(product_id: bouquet.id, size: :large, price: "60.00", draft: false))

    plant = generate(product(product_category_id: plants.id, draft: false))
    generate(product_variant(product_id: plant.id, price: "18.00", draft: false))

    {:ok, view, _html} = live(conn, ~p"/en")

    assert has_element?(view, "h1 + p", "from €42.")
  end

  test "delivery and pickup shows the next open day", %{conn: conn} do
    shop_calendar(same_day: false)
    tomorrow = Date.add(Edenflowers.ShopTime.today(), 1)

    {:ok, view, _html} = live(conn, ~p"/en")

    assert has_element?(view, "#location-heading + dl dd", "#{tomorrow.day}.#{tomorrow.month}.")
  end

  test "the subscription section lists subscribable products", %{conn: conn} do
    category = generate(product_category(visibility: :public))

    product =
      generate(product(product_category_id: category.id, subscribable: true, name: "Florist's choice", draft: false))

    generate(product_variant(product_id: product.id, draft: false))

    {:ok, view, _html} = live(conn, ~p"/en")

    assert has_element?(view, "#subscription", "Florist's choice")
    assert has_element?(view, ~s(nav a[href="#subscription"]))
  end

  test "states the shop's details to search engines, matching the footer", %{conn: conn} do
    html = conn |> get(~p"/en") |> html_response(200)

    assert %{"@type" => "Florist", "telephone" => "+358402209494", "openingHoursSpecification" => [weekdays, saturday]} =
             json_ld(html)

    assert %{"opens" => "10:00", "closes" => "18:00"} = weekdays
    assert %{"dayOfWeek" => ["Saturday"], "closes" => "15:00"} = saturday
    assert html =~ "Mon–Fri: 10:00–18:00"
    assert html =~ "Sat: 10:00–15:00"
  end

  defp json_ld(html) do
    case Regex.run(~r|<script type="application/ld\+json">(.*?)</script>|s, html) do
      [_, json] -> Jason.decode!(json)
      nil -> nil
    end
  end
end
