defmodule EdenflowersWeb.Marketing.FaqLiveTest do
  use EdenflowersWeb.ConnCase, async: false

  import Generator
  import Phoenix.LiveViewTest

  alias Edenflowers.Orders.Subscription

  test "the card answer gives each card size's message limit and price from the catalogue", %{conn: conn} do
    cards = generate(product_category(slug: "cards", visibility: :public))
    card = generate(product(product_category_id: cards.id, draft: false))
    generate(product_variant(product_id: card.id, draft: false, size: :small, price: "3.90"))
    generate(product_variant(product_id: card.id, draft: false, size: :large, price: "6.50"))

    {:ok, view, _html} = live(conn, ~p"/en/faq")

    assert has_element?(view, "#ordering li", "Small: up to 80 characters, from €3.90")
    assert has_element?(view, "#ordering li", "Large: up to 200 characters, from €6.50")
    refute has_element?(view, "#ordering li", "Medium")
  end

  test "the delivery answer reads the distance and fee from the delivery option", %{conn: conn} do
    generate(
      fulfillment_option(
        fulfillment_method: :delivery,
        rate_type: :dynamic,
        max_dist_km: 17,
        free_dist_km: 4,
        base_price: "5.00",
        price_per_km: "1.20"
      )
    )

    {:ok, view, _html} = live(conn, ~p"/en/faq")

    assert has_element?(
             view,
             "#delivery details",
             "Within 17 km of the shop, for €5.00 plus €1.20 per km"
           )

    assert has_element?(view, "#delivery details", "delivered free within 4 km")
  end

  test "the cancel answer gives the change deadline and links the terms", %{conn: conn} do
    days = Subscription.change_deadline_days()

    {:ok, view, _html} = live(conn, ~p"/en/faq")

    assert has_element?(view, "#ordering details", "until #{days} days before delivery or pickup")
    assert has_element?(view, ~s|#ordering a[href="/en/terms#cancellation"]|)
  end

  test "emits FAQPage structured data with the page's questions as plain text", %{conn: conn} do
    days = Subscription.change_deadline_days()

    html = conn |> get(~p"/en/faq") |> html_response(200)

    [json] =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query(~s|script[type="application/ld+json"]|)
      |> Enum.map(&LazyHTML.text/1)

    data = Jason.decode!(json)
    assert %{"@context" => "https://schema.org", "@type" => "FAQPage", "mainEntity" => questions} = data

    cancel = Enum.find(questions, &(&1["name"] == "Can I cancel an order I made online?"))
    assert %{"@type" => "Question", "acceptedAnswer" => %{"@type" => "Answer", "text" => text}} = cancel
    assert text =~ "until #{days} days before"
    refute text =~ "<"

    assert Enum.any?(questions, &(&1["name"] == "When do I pay?"))
  end

  test "the delivery answer gives the same-day deadline from the shop calendar", %{conn: conn} do
    Generator.shop_calendar(same_day: true, order_deadline: ~T[11:30:00])

    {:ok, view, _html} = live(conn, ~p"/en/faq")

    assert has_element?(view, "details", "Order by 11:30")
  end

  test "the delivery answer leaves out same day when the shop has it off", %{conn: conn} do
    Generator.shop_calendar(same_day: false)

    {:ok, view, _html} = live(conn, ~p"/en/faq")

    assert has_element?(view, "details", "The earliest delivery is the next day the shop is open.")
    refute has_element?(view, "details", "same day")
  end
end
