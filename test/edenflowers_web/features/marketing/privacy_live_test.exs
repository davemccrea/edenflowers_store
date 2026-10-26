defmodule EdenflowersWeb.Marketing.PrivacyLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  alias EdenflowersWeb.Business

  test "identifies the controller and the confirmed hosting arrangement", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/privacy")

    assert has_element?(view, "#controller", "Jennie McCrea, trading as Eden Flowers")
    assert has_element?(view, "#controller", Business.business_id())
    assert has_element?(view, "#controller", Business.registered_address())
    assert has_element?(view, ~s|#controller a[href="mailto:#{Business.email()}"]|)
    assert has_element?(view, ~s|#controller a[href="tel:#{Business.phone()}"]|)
    assert has_element?(view, "#sharing", "Our main customer database is hosted by Hetzner in Finland.")
  end

  test "keeps outstanding legal details visibly marked as a draft", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/privacy")

    assert has_element?(view, "#privacy-draft", "Draft — not a completed privacy notice")

    for detail <- ["recipients", "transfers", "retention", "fraud-checks"] do
      assert has_element?(view, ~s|[data-draft-detail="#{detail}"]|, "To confirm:")
    end

    refute has_element?(view, "#retention", "7 years")
    refute has_element?(view, "#sharing", "all data stays in the EU")
  end

  test "records the two-week photo period without implying cleanup is implemented", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/privacy")

    assert has_element?(view, "#retention", "retention period for delivery photographs is two weeks")
    assert has_element?(view, ~s|[data-draft-detail="photo-cleanup"]|, "To implement: automatic deletion")
    refute has_element?(view, ~s|[data-draft-detail="retention"]|, "photographs")
  end

  test "describes current collection and sharing rather than the older assumptions", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/privacy")

    assert has_element?(view, "#information", "Gift-recipient details come from the customer.")
    assert has_element?(view, "#information", "photograph flowers left at the door")
    assert has_element?(view, "#information", "Newsletters require your consent.")
    assert has_element?(view, "#information", "contracts or steps towards one")
    assert has_element?(view, "#information", "accounting relies on legal obligations")
    assert has_element?(view, "#information", "Recipient deliveries, customer administration and website security")
    assert has_element?(view, "#information", "our legitimate interests")
    assert has_element?(view, "#information", "Required details are necessary to fulfil purchases.")
    assert has_element?(view, "#sharing", "order count, latest order date and total spent")
    assert has_element?(view, "#sharing", "including non-subscribers")
    assert has_element?(view, "#sharing", "Only subscribers receive newsletters.")
    assert has_element?(view, "#sharing", "brand and last four digits")
    assert has_element?(view, "#sharing", "HERE checks delivery addresses and calculates distances")
    assert has_element?(view, "#sharing", "Mapbox displays delivery maps")
    assert has_element?(view, "#sharing", "shares the destination with Google Maps")
    assert has_element?(view, "#sharing", "Cloudflare")
    assert has_element?(view, "#cookies", "sign-in for 30 days")
    assert has_element?(view, "#cookies", "Stripe loads site-wide")
    assert has_element?(view, "#cookies", "IP addresses, browser information and submitted data")
    assert has_element?(view, "#rights", "normally respond within one month")
    assert has_element?(view, ~s|#rights a[href="https://tietosuoja.fi/en"]|)
  end

  test "keeps the notice concise without dropping data rights", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/en/privacy")

    words =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("#main-content")
      |> LazyHTML.text()
      |> String.split(~r/\s+/, trim: true)

    assert length(words) < 450

    for right <- ["access", "correction", "deletion", "restriction", "portability", "object"] do
      assert has_element?(view, "#rights", right)
    end

    assert has_element?(view, "#rights", "verify your identity")
    assert has_element?(view, "#rights", "withdraw newsletter consent")
    assert has_element?(view, "#rights", "does not affect earlier lawful processing")
    assert has_element?(view, "#rights", Business.email())
  end

  test "uses the Terms page's section navigation and reading style", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/en/privacy")
    document = LazyHTML.from_document(html)
    sections = ["controller", "information", "sharing", "cookies", "retention", "rights"]

    assert document |> LazyHTML.query("nav[aria-labelledby=privacy-nav-heading] a") |> LazyHTML.attribute("href") ==
             Enum.map(sections, &"##{&1}")

    for section <- sections do
      assert has_element?(view, "##{section} > h2.section-title")
      assert has_element?(view, "##{section} > div.text-base.leading-relaxed")
    end

    refute has_element?(view, "#main-content details")
  end

  test "is available in each language route with alternate and signup links", %{conn: conn} do
    for language <- ["en", "sv", "fi"] do
      path = "/#{language}/privacy"
      {:ok, view, _html} = live(conn, path)

      assert has_element?(view, "#privacy-draft")
      assert has_element?(view, ~s|footer a[href="#{path}"]|, "Privacy policy (draft)")
      assert has_element?(view, ~s|#newsletter-form a[href="#{path}"]|)

      for alternate <- ["en", "sv", "fi"] do
        assert has_element?(view, ~s|#locale-picker-footer option[value="/#{alternate}/privacy"]|)
      end

      html = conn |> get(path) |> html_response(200)

      for alternate <- ["en", "sv", "fi"] do
        assert html =~ ~s|hreflang="#{alternate}" href="http://localhost:4002/#{alternate}/privacy"|
      end
    end
  end

  test "the incomplete policy is noindex and not included in the sitemap", %{conn: conn} do
    for language <- ["en", "sv", "fi"] do
      html = conn |> get("/#{language}/privacy") |> html_response(200)
      assert html =~ ~s|<meta name="robots" content="noindex"|
    end

    terms = conn |> get(~p"/en/terms") |> html_response(200)
    refute terms =~ ~s|<meta name="robots" content="noindex"|

    xml = conn |> get(~p"/sitemap.xml") |> response(200)
    refute xml =~ "/privacy"
  end

  test "checkout links to the draft alongside the newsletter preference", %{conn: conn} do
    product = generate(product())
    variant = generate(product_variant(product_id: product.id))
    generate(fulfillment_option())
    order = generate(order())
    Edenflowers.Orders.add_line_item!(order.id, variant.id, 1, authorize?: false)

    conn = Plug.Test.init_test_session(conn, %{order_id: order.id})
    {:ok, view, _html} = live(conn, ~p"/checkout")

    assert has_element?(view, ~s|[data-testid="newsletter-opt-in-checkbox"]|)
    assert has_element?(view, ~s|[data-testid="checkout-form-1"] a[href="/en/privacy"]|, "Privacy policy (draft)")
  end
end
