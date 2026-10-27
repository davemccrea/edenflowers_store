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
    assert has_element?(view, "#sharing", "Hetzner hosts our main customer database in Finland.")
  end

  test "shows the update date without draft caveats or internal work notes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/privacy")

    assert has_element?(view, "#notice-updated", "Updated 26 October 2026.")

    for caveat <- ["draft", "confirming", "under review", "need checking", "not yet", "intended"] do
      refute has_element?(view, "#main-content", caveat)
    end

    refute has_element?(view, "#privacy-draft")
    refute has_element?(view, "[data-draft-detail]")
    refute has_element?(view, "#main-content", "To confirm:")
    refute has_element?(view, "#main-content", "To implement:")

    refute has_element?(view, "#retention", "7 years")
    refute has_element?(view, "#sharing", "all data stays in the EU")
  end

  test "states accounting requirements without promising unimplemented expiry", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/privacy")

    refute has_element?(view, "#retention", "two weeks")
    assert has_element?(view, "#retention", "end of the calendar year in which the financial year ended")
    assert has_element?(view, "#retention", "ten years from the financial-year end")
    assert has_element?(view, "#retention", "does not automatically apply to delivery-only details")
    refute has_element?(view, "#retention", "until it is, ask us")
    refute has_element?(view, "#retention", "Enquiries: twelve months")
    refute has_element?(view, "#retention", "our accountant decides which")

    for category <- [
          "Accounting",
          "Newsletters",
          "Error reports",
          "Routine database backups"
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
    assert has_element?(view, "#information", "coordinates for calculating distance")
    assert has_element?(view, "#information", "our contract with you or steps you request before it")
    assert has_element?(view, "#information", "Accounting records: our legal obligation")
    assert has_element?(view, "#information", "Our legal bases are")

    assert has_element?(view, "#information", "legitimate interests: fulfilling gifts, documenting delivery")

    assert has_element?(
             view,
             "#information",
             "administering purchases, handling complaints and preventing website abuse"
           )

    assert has_element?(
             view,
             "#information",
             "We cannot fulfil purchases without necessary contact and delivery details"
           )

    assert has_element?(view, "#information", "Newsletter signup is optional")
    assert has_element?(view, "#information", "Instagram handles are optional")
    assert has_element?(view, "#information", "Checkout may create an account")
    assert has_element?(view, "#sharing", "contact details, language and purchase statistics")
    assert has_element?(view, "#sharing", "including for non-subscribers with phone numbers")
    assert has_element?(view, "#sharing", "Newsletters go only to subscribers.")
    assert has_element?(view, "#sharing", "limited card details, not full card numbers or security codes")
    assert has_element?(view, "#sharing", "Mapping services receive delivery addresses or coordinates")
    assert has_element?(view, "#sharing", "Website-security and mailbox providers handle traffic and emails")
    refute has_element?(view, "#sharing", "Google Maps")
    assert has_element?(view, "#sharing", "Our accountant receives monthly purchase and payment records")
    assert has_element?(view, "#sharing", "photos may go to the purchaser, not necessarily the recipient")
    assert has_element?(view, "#sharing", "cannot be recalled")
    refute has_element?(view, "#sharing", "emailed to the recipient")
    assert has_element?(view, "#cookies", "sign-in for up to 30 days")
    assert has_element?(view, "#cookies", "Stripe loads site-wide")
    assert has_element?(view, "#cookies", "We do not use analytics or advertising cookies")
    assert has_element?(view, "#cookies", "Blocking cookies in your browser")
    assert has_element?(view, "#cookies", "IP addresses, browser details and form data")
    assert has_element?(view, "#cookies", "Browser settings do not replace required consent")
    assert has_element?(view, "#rights", "Requests are normally free")
    assert has_element?(view, "#rights", "Within one month we respond or explain a lawful extension")
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

    assert length(words) < 650

    for right <- ["access", "correction", "deletion", "restriction", "portability", "Object"] do
      assert has_element?(view, "#rights", right)
    end

    assert has_element?(view, "#rights", "verify your identity")
    assert has_element?(view, "#rights", "withdraw newsletter consent")
    assert has_element?(view, "#rights", "Earlier lawful processing is unaffected")
    assert has_element?(view, "#rights", Business.email())
  end

  test "groups purposes, providers, cookies and rights into scannable bullet points", %{conn: conn} do
    for language <- ["en", "sv", "fi"] do
      {:ok, view, html} = live(conn, "/#{language}/privacy")
      document = LazyHTML.from_document(html)

      for {section, count} <- [{"information", 7}, {"sharing", 6}, {"cookies", 4}, {"retention", 4}, {"rights", 3}] do
        assert has_element?(view, "##{section} ul.list-disc.space-y-3")
        assert document |> LazyHTML.query("##{section} ul > li") |> Enum.count() == count
      end

      refute has_element?(view, "#controller ul")
    end
  end

  test "uses formal sans-serif headings and section navigation", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/en/privacy")
    document = LazyHTML.from_document(html)
    sections = ["controller", "information", "sharing", "cookies", "retention", "rights"]

    assert document |> LazyHTML.query("nav[aria-labelledby=privacy-nav-heading] a") |> LazyHTML.attribute("href") ==
             Enum.map(sections, &"##{&1}")

    assert has_element?(view, "#main-content h1.font-sans.font-semibold")
    assert has_element?(view, "#privacy-nav .category-index__name.font-sans.text-sm")
    refute has_element?(view, "#main-content .page-title, #main-content .section-title, #privacy-nav .font-serif")

    for section <- sections do
      assert has_element?(view, "##{section} > h2.font-sans.font-semibold")
      assert has_element?(view, "##{section} > div.text-base-content.text-base.font-normal.leading-relaxed")
      refute has_element?(view, "##{section} > div[class*=\"text-base-content/80\"]")
    end

    refute has_element?(view, "#main-content details")
  end

  test "is available in each language route with alternate and signup links", %{conn: conn} do
    for {language, title} <- [{"en", "Privacy policy"}, {"sv", "Integritetspolicy"}, {"fi", "Tietosuojaseloste"}] do
      path = "/#{language}/privacy"
      {:ok, view, _html} = live(conn, path)

      refute has_element?(view, "#privacy-draft")
      assert has_element?(view, ~s|footer a[href="#{path}"]|, title)
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

  test "translates privacy headings, body and interpolated contact instructions", %{conn: conn} do
    for {language, title, hosting, contact, updated} <- [
          {"sv", "Integritetspolicy", "Vår huvudsakliga kunddatabas finns hos Hetzner i Finland.",
           "Mejla #{Business.email()} för att:", "Uppdaterad 26 oktober 2026."},
          {"fi", "Tietosuojaseloste", "Pääasiallinen asiakastietokantamme sijaitsee Hetznerin palvelimilla Suomessa.",
           "Lähetä sähköpostia osoitteeseen #{Business.email()}, jos haluat:", "Päivitetty 26. lokakuuta 2026."}
        ] do
      {:ok, view, _html} = live(conn, "/#{language}/privacy")

      assert has_element?(view, "h1", title)
      assert has_element?(view, "#sharing", hosting)
      assert has_element?(view, "#rights", contact)
      assert has_element?(view, "#notice-updated", updated)
      refute has_element?(view, "#main-content", "Our legal bases are:")
      refute has_element?(view, "#main-content", "Newsletters require your consent.")
    end
  end

  test "keeps the existing noindex and sitemap settings", %{conn: conn} do
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
