defmodule EdenflowersWeb.Marketing.HomeLiveTest do
  use EdenflowersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Generator

  test "delivery metadata uses the configured free radius in every language", %{conn: conn} do
    generate(fulfillment_option(fulfillment_method: :delivery, rate_type: :dynamic, free_dist_km: 8))

    for path <- ["/en", "/sv", "/fi"] do
      html = conn |> get(path) |> html_response(200)
      description = page_description(html)

      assert description =~ "8 km"
      assert description =~ "Minimossen"
      refute description =~ "5 km"
    end

    {:ok, view, _html} = live(conn, ~p"/en")
    assert has_element?(view, "#location-heading + dl", "Free within 8 km for chosen bouquets")
    assert page_description(conn |> get(~p"/en") |> html_response(200)) =~ "on selected bouquets."
  end

  test "delivery metadata makes no free-delivery claim when the radius is zero", %{conn: conn} do
    generate(fulfillment_option(fulfillment_method: :delivery, rate_type: :dynamic, free_dist_km: 0))

    assert_no_free_delivery_metadata(conn)
  end

  test "delivery metadata makes no free-delivery claim without a distance-priced option", %{conn: conn} do
    assert_no_free_delivery_metadata(conn)
  end

  defp assert_no_free_delivery_metadata(conn) do
    for path <- ["/en", "/sv", "/fi"] do
      description = page_description(conn |> get(path) |> html_response(200))

      assert description =~ "Eden Flowers"
      refute description =~ "Minimossen"
      refute description =~ "km"
    end
  end

  defp page_description(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query(~s(meta[name="description"]))
    |> LazyHTML.attribute("content")
    |> List.first()
  end

  test "the hero quotes the cheapest bouquet, not a cheaper product in another category", %{conn: conn} do
    bouquets = generate(product_category(slug: "bouquets", visibility: :public))
    plants = generate(product_category(visibility: :public))

    bouquet = generate(product(product_category_id: bouquets.id, draft: false))
    generate(product_variant(product_id: bouquet.id, price: "42.00", draft: false))
    generate(product_variant(product_id: bouquet.id, size: :large, price: "60.00", draft: false))

    plant = generate(product(product_category_id: plants.id, draft: false))
    generate(product_variant(product_id: plant.id, price: "18.00", draft: false))

    {:ok, view, _html} = live(conn, ~p"/en")

    assert has_element?(view, "h1 + p", "from 42 €.")
  end

  test "favourites name each product's category, and the heading says bouquets only when all of them are",
       %{conn: conn} do
    bouquets = generate(product_category(slug: "bouquets", name: "Bouquets", visibility: :public))
    bouquet = generate(product(product_category_id: bouquets.id, featured: true, draft: false))
    generate(product_variant(product_id: bouquet.id, draft: false))

    {:ok, view, _html} = live(conn, ~p"/en")

    assert has_element?(view, "#store h2", "Favourite bouquets")
    assert has_element?(view, "#store p", "Bouquets")

    plants = generate(product_category(name: "Plants", visibility: :public))
    plant = generate(product(product_category_id: plants.id, featured: true, draft: false))
    generate(product_variant(product_id: plant.id, draft: false))

    {:ok, view, _html} = live(conn, ~p"/en")

    assert has_element?(view, "#store h2", ~r/^\s*Favourites\s*$/)
    assert has_element?(view, "#store p", "Plants")
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
    refute has_element?(view, ~s(nav[aria-label="What are the flowers for?"]))
  end

  test "English visitors get a translation beneath each quote; others see the original alone", %{conn: conn} do
    {:ok, en, _html} = live(conn, ~p"/en")
    assert has_element?(en, "#review-pages", "So glad you're here")

    {:ok, sv, _html} = live(conn, ~p"/sv")
    refute has_element?(sv, "#review-pages", "So glad you're here")
    assert has_element?(sv, "#review-pages", "räddare i nöden")
  end

  test "customer quotes keep original wording and read as complete excerpts", %{conn: conn} do
    originals =
      Regex.scan(~r/”([^”]+)”/u, File.read!("docs/feedback.md"), capture: :all_but_first)
      |> List.flatten()

    for locale <- ["en", "sv", "fi"] do
      {:ok, view, _html} = live(conn, "/#{locale}")

      quotes =
        view
        |> render()
        |> LazyHTML.from_document()
        |> LazyHTML.query("#review-pages blockquote")
        |> Enum.map(&(LazyHTML.text(&1) |> String.trim()))

      assert length(quotes) == 9

      for quote <- quotes do
        pattern =
          quote
          |> String.split()
          |> Enum.map_join("\\s+(?:.*?\\s+)?", &Regex.escape/1)
          |> then(&Regex.compile!(&1, "s"))

        assert Enum.any?(originals, &Regex.match?(pattern, &1)),
               "Customer quote changes words or their order from feedback.md: #{inspect(quote)}"

        refute quote =~ "…"
        assert String.length(quote) <= 280
      end
    end
  end

  test "states the shop's details to search engines, matching the footer", %{conn: conn} do
    html = conn |> get(~p"/en") |> html_response(200)

    assert [
             %{"@type" => "WebSite", "name" => "Eden Flowers"},
             %{
               "@type" => "Florist",
               "telephone" => "+358402209494",
               "openingHoursSpecification" => [weekdays, saturday]
             }
           ] = json_ld(html)

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

  describe "footer newsletter signup" do
    use Oban.Testing, repo: Edenflowers.Repo

    test "subscribes the address and queues its welcome code", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en")

      view |> form("#newsletter-form", %{"email_address" => "footer@example.com"}) |> render_submit()

      assert render(view) =~ "Your 15% off code is on its way"
      {:ok, user} = Edenflowers.Accounts.get_user_by_email("footer@example.com", authorize?: false)
      assert user.newsletter_opt_in

      assert_enqueued(
        worker: Edenflowers.Pricing.Workers.SendNewsletterPromoEmail,
        args: %{"email" => "footer@example.com"}
      )
    end

    test "a malformed address is turned away without saving or promising a code", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en")

      view |> form("#newsletter-form", %{"email_address" => "not an email"}) |> render_submit()

      refute has_element?(view, "#newsletter-signup-form", "Your 15% off code is on its way")
      assert has_element?(view, "#newsletter-form [role=alert]", "Enter a valid email address.")
      assert {:error, _} = Edenflowers.Accounts.get_user_by_email("not an email", authorize?: false)
      refute_enqueued(worker: Edenflowers.Pricing.Workers.SendNewsletterPromoEmail)
    end

    test "a returning subscriber is matched whatever the case of their address", %{conn: conn} do
      {:ok, user} = Edenflowers.Accounts.subscribe_to_newsletter("Footer@Example.com", "en-GB", authorize?: false)
      {:ok, view, _html} = live(conn, ~p"/en")

      view |> form("#newsletter-form", %{"email_address" => "footer@example.com"}) |> render_submit()

      {:ok, matched} = Edenflowers.Accounts.get_user_by_email("FOOTER@example.com", authorize?: false)
      assert matched.id == user.id
    end
  end
end
