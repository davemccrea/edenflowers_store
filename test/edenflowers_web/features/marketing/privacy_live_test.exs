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

  test "states accounting requirements without promising unimplemented expiry", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/privacy")

    refute has_element?(view, "#retention", "two weeks")
    assert has_element?(view, "#retention", "end of the calendar year in which the financial year ended")
    assert has_element?(view, "#retention", "ten years from the financial-year end")
    assert has_element?(view, "#retention", "Delivery photos: kept with the order until you ask us to delete them.")
    assert has_element?(view, "#retention", "we keep until you ask us to delete it")
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

  test "states its legal bases, who receives data and how to exercise rights", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/privacy")

    assert has_element?(view, "#information", "our contract with you or steps you request before it")
    assert has_element?(view, "#information", "Accounting records: our legal obligation")
    assert has_element?(view, "#information", "legitimate interests: fulfilling gifts, documenting delivery")
    assert has_element?(view, "#information", "Newsletters require your consent.")
    assert has_element?(view, "#sharing", "limited card details, not full card numbers or security codes")
    assert has_element?(view, "#sharing", "Our accountant receives monthly purchase and payment records")
    assert has_element?(view, "#cookies", "We do not use analytics or advertising cookies")
    assert has_element?(view, "#rights", "Within one month we respond or explain a lawful extension")
    assert has_element?(view, ~s|#rights a[href="https://tietosuoja.fi/en"]|, "Office of the Data Protection Ombudsman")
  end

  test "states every data right and how to exercise it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/privacy")

    for right <- ["access", "correction", "deletion", "restriction", "portability", "Object"] do
      assert has_element?(view, "#rights", right)
    end

    assert has_element?(view, "#rights", "verify your identity")
    assert has_element?(view, "#rights", "withdraw newsletter consent")
    assert has_element?(view, "#rights", "Earlier lawful processing is unaffected")
    assert has_element?(view, "#rights", Business.email())
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

  test "interpolates contact instructions into complete translated sentences", %{conn: conn} do
    for {language, contact} <- [
          {"sv", "Mejla #{Business.email()} för att:"},
          {"fi", "Lähetä sähköpostia osoitteeseen #{Business.email()}, jos haluat:"}
        ] do
      {:ok, view, _html} = live(conn, "/#{language}/privacy")

      assert has_element?(view, "#rights", contact)
    end
  end

  test "is indexable and in the sitemap in every language", %{conn: conn} do
    for language <- ["en", "sv", "fi"] do
      html = conn |> get("/#{language}/privacy") |> html_response(200)
      refute html =~ ~s|<meta name="robots" content="noindex"|
    end

    xml = conn |> get(~p"/sitemap.xml") |> response(200)
    assert xml =~ "/en/privacy"
    assert xml =~ "/sv/privacy"
    assert xml =~ "/fi/privacy"
  end

  test "checkout links to the privacy policy alongside the newsletter preference", %{conn: conn} do
    product = generate(product())
    variant = generate(product_variant(product_id: product.id))
    generate(fulfillment_option())
    order = generate(order())
    Edenflowers.Orders.add_line_item!(order.id, variant.id, 1, authorize?: false)

    conn = with_cart(conn, order)
    {:ok, view, _html} = live(conn, ~p"/checkout")

    assert has_element?(view, ~s|[data-testid="newsletter-opt-in-checkbox"]|)
    assert has_element?(view, ~s|[data-testid="checkout-form-1"] a[href="/en/privacy"]|, "Privacy policy")
    refute has_element?(view, ~s|[data-testid="checkout-form-1"] a[href="/en/privacy"]|, "(draft)")
  end
end
