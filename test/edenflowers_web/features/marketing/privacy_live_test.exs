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

  test "marks the notice as a draft without leaving internal publication notes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/privacy")

    assert has_element?(view, "#notice-status", "still a draft")
    refute has_element?(view, "#privacy-draft")
    refute has_element?(view, "[data-draft-detail]")
    refute has_element?(view, "#main-content", "To confirm:")
    refute has_element?(view, "#main-content", "To implement:")

    refute has_element?(view, "#retention", "7 years")
    refute has_element?(view, "#sharing", "all data stays in the EU")
  end

  test "distinguishes intended retention from current deletion and accounting requirements", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/privacy")

    assert has_element?(view, "#retention", "Delivery photographs: intended retention is two weeks")
    assert has_element?(view, "#retention", "Routine deletion is not yet implemented")
    assert has_element?(view, "#retention", "not yet routinely deleted")
    assert has_element?(view, "#retention", "calendar year in which the financial year ended")
    assert has_element?(view, "#retention", "ten years from the financial-year end")
    assert has_element?(view, "#retention", "do not automatically require us to retain delivery-only details")
    refute has_element?(view, "#retention", "until it is, ask us")
    refute has_element?(view, "#retention", "Enquiries: twelve months")
    refute has_element?(view, "#retention", "our accountant decides which")

    for category <- [
          "Accounting records",
          "Customer, subscription and enquiry records",
          "Newsletters",
          "Error reports",
          "Backups",
          "Delivery photographs"
        ] do
      assert has_element?(view, "#retention li", category)
    end
  end

  test "describes current collection and sharing rather than the older assumptions", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/privacy")

    assert has_element?(view, "#information", "Gift-recipient details come from the customer.")
    assert has_element?(view, "#information", "photograph flowers left at the door")
    assert has_element?(view, "#information", "Newsletters require your consent.")
    assert has_element?(view, "#information", "Instagram handle")
    assert has_element?(view, "#information", "coordinates we look up to calculate delivery distance")
    assert has_element?(view, "#information", "the contract with you or steps taken at your request")
    assert has_element?(view, "#information", "Accounting records: our legal obligation")
    assert has_element?(view, "#information", "Our legal bases are")

    assert has_element?(
             view,
             "#information",
             "legitimate interests in fulfilling gifts and handling purchases and complaints"
           )

    assert has_element?(view, "#information", "legitimate interest in preventing abuse")
    assert has_element?(view, "#information", "we cannot complete your purchase")
    assert has_element?(view, "#information", "Newsletter signup is optional")
    assert has_element?(view, "#information", "optional Instagram handle")
    assert has_element?(view, "#information", "Checkout can create a customer account without separate registration")
    assert has_element?(view, "#sharing", "order count, latest order date and total spent")
    assert has_element?(view, "#sharing", "including non-subscribers")
    assert has_element?(view, "#sharing", "Only subscribers receive newsletters.")
    assert has_element?(view, "#sharing", "brand and last four digits")
    assert has_element?(view, "#sharing", "HERE checks delivery addresses and calculates distances")
    assert has_element?(view, "#sharing", "Mapbox displays delivery maps")
    assert has_element?(view, "#sharing", "Opening directions shares the destination with Google Maps")
    assert has_element?(view, "#sharing", "Cloudflare")
    assert has_element?(view, "#sharing", "Our accountant receives purchase and payment records")
    assert has_element?(view, "#sharing", "hosts the #{Business.email()} mailbox")
    assert has_element?(view, "#sharing", "emailed to the purchasing customer, who may not be the recipient")
    assert has_element?(view, "#sharing", "cannot be recalled")
    refute has_element?(view, "#sharing", "emailed to the recipient")
    assert has_element?(view, "#sharing", "process data outside the EEA")
    assert has_element?(view, "#sharing", "how to obtain a copy")
    assert has_element?(view, "#cookies", "sign-in for up to 30 days")
    assert has_element?(view, "#cookies", "Stripe loads site-wide")
    assert has_element?(view, "#cookies", "We do not use analytics or advertising cookies")
    assert has_element?(view, "#cookies", "block or delete cookies in your browser settings")
    assert has_element?(view, "#cookies", "IP addresses, browser information and submitted form data")
    assert has_element?(view, "#cookies", "consent requirements are still being assessed")
    assert has_element?(view, "#cookies", "Browser settings do not replace consent")
    assert has_element?(view, "#rights", "Requests are normally free")
    assert has_element?(view, "#rights", "respond within one month or explain any lawful extension within that month")
    assert has_element?(view, ~s|#rights a[href="https://tietosuoja.fi/en"]|, "Office of the Data Protection Ombudsman")
    assert has_element?(view, ~s|#rights a[href="/en/terms"]|)
  end

  test "keeps the notice readable without dropping data rights", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/en/privacy")

    words =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("#main-content")
      |> LazyHTML.text()
      |> String.split(~r/\s+/, trim: true)

    assert length(words) < 800

    for right <- ["access", "correction", "deletion", "restriction", "portability", "Object"] do
      assert has_element?(view, "#rights", right)
    end

    assert has_element?(view, "#rights", "verify your identity")
    assert has_element?(view, "#rights", "withdraw newsletter consent")
    assert has_element?(view, "#rights", "does not affect earlier lawful processing")
    assert has_element?(view, "#rights", Business.email())
  end

  test "groups purposes, providers, cookies and rights into scannable bullet points", %{conn: conn} do
    for language <- ["en", "sv", "fi"] do
      {:ok, view, html} = live(conn, "/#{language}/privacy")
      document = LazyHTML.from_document(html)

      for {section, count} <- [{"information", 7}, {"sharing", 10}, {"cookies", 4}, {"retention", 6}, {"rights", 3}] do
        assert has_element?(view, "##{section} ul.list-disc.space-y-3")
        assert document |> LazyHTML.query("##{section} ul > li") |> Enum.count() == count
      end

      refute has_element?(view, "#controller ul")
    end
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

      refute has_element?(view, "#privacy-draft")
      assert has_element?(view, ~s|footer a[href="#{path}"]|, "Privacy policy")
      refute has_element?(view, "#main-content", "(draft)")
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

  test "checkout links to the privacy policy alongside the newsletter preference", %{conn: conn} do
    product = generate(product())
    variant = generate(product_variant(product_id: product.id))
    generate(fulfillment_option())
    order = generate(order())
    Edenflowers.Orders.add_line_item!(order.id, variant.id, 1, authorize?: false)

    conn = Plug.Test.init_test_session(conn, %{order_id: order.id})
    {:ok, view, _html} = live(conn, ~p"/checkout")

    assert has_element?(view, ~s|[data-testid="newsletter-opt-in-checkbox"]|)
    assert has_element?(view, ~s|[data-testid="checkout-form-1"] a[href="/en/privacy"]|, "Privacy policy")
    refute has_element?(view, ~s|[data-testid="checkout-form-1"] a[href="/en/privacy"]|, "(draft)")
  end
end
