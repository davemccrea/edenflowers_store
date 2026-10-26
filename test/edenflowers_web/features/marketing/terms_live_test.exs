defmodule EdenflowersWeb.Marketing.TermsLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  alias Edenflowers.Orders.Subscription

  test "shows the last-updated date beneath the title", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/terms")

    assert has_element?(view, "#main-content h1 + #notice-updated", "Updated 26 October 2026.")
  end

  test "reads the delivery distance and cancellation deadline live", %{conn: conn} do
    generate(fulfillment_option(fulfillment_method: :delivery, rate_type: :dynamic, max_dist_km: 17))
    days = Subscription.change_deadline_days()

    {:ok, view, _html} = live(conn, ~p"/en/terms")

    assert has_element?(view, "#delivery", "I deliver within 17 km driving distance of the shop")
    assert has_element?(view, "#cancellation", "until #{days} days before delivery or pickup")
    assert has_element?(view, "#seller", EdenflowersWeb.Business.business_id())
  end

  test "the index follows the general terms, special services and seller details", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/en/terms")
    document = LazyHTML.from_document(html)

    sections = [
      {"payment", "Prices and payment"},
      {"delivery", "Delivery and pickup"},
      {"quality", "Quality"},
      {"cancellation", "Changes and cancellations"},
      {"subscriptions", "Subscriptions"},
      {"weddings", "Weddings"},
      {"courses", "Courses"},
      {"seller", "Seller and contact details"}
    ]

    assert document |> LazyHTML.query("nav[aria-labelledby=terms-nav-heading] a") |> LazyHTML.attribute("href") ==
             Enum.map(sections, fn {id, _title} -> "##{id}" end)

    assert document |> LazyHTML.query("#main-content section > h2") |> Enum.map(&LazyHTML.text/1) ==
             Enum.map(sections, fn {_id, title} -> title end)

    for {id, title} <- sections do
      assert has_element?(view, "##{id} > h2", title)
    end
  end

  test "shares the FAQ's formal sans-serif typography and navigation", %{conn: conn} do
    {:ok, _faq, faq_html} = live(conn, ~p"/en/faq")
    {:ok, view, terms_html} = live(conn, ~p"/en/terms")

    faq_nav = faq_html |> LazyHTML.from_document() |> LazyHTML.query("#faq-nav")
    terms_nav = terms_html |> LazyHTML.from_document() |> LazyHTML.query("#terms-nav")

    assert LazyHTML.attribute(terms_nav, "class") == LazyHTML.attribute(faq_nav, "class")
    assert LazyHTML.attribute(terms_nav, "phx-hook") == LazyHTML.attribute(faq_nav, "phx-hook")
    assert has_element?(view, "#terms-nav.hidden.md\\:block.sticky")
    assert has_element?(view, "#terms-nav .category-index__link .category-index__name.font-sans.text-sm")
    assert has_element?(view, "#main-content h1.font-sans.font-semibold")
    assert has_element?(view, "#payment > h2.font-sans.font-semibold.mb-6")
    refute has_element?(view, "#main-content .page-title, #main-content .section-title, #terms-nav .font-serif")
    assert LazyHTML.query(LazyHTML.from_document(faq_html), "#faq-nav .category-index__name.font-sans.text-sm") != []
    assert has_element?(view, "#payment > div.text-base-content.text-base.font-normal.leading-relaxed")
    refute has_element?(view, "#main-content section > div[class*=\"text-base-content/80\"]")
    assert has_element?(view, "#checkout-payments > h3.font-sans.text-base.font-medium")
    refute has_element?(view, "#main-content details")
  end

  test "groups multiple rules into bullet lists in every language", %{conn: conn} do
    for path <- ["/en/terms", "/sv/kopvillkor", "/fi/toimitusehdot"] do
      {:ok, view, html} = live(conn, path)
      document = LazyHTML.from_document(html)

      for section <- ["checkout-payments", "invoices", "delivery-problems", "quality"] do
        assert has_element?(view, "##{section} ul.list-disc")
        assert document |> LazyHTML.query("##{section} ul > li") |> Enum.count() == 2
      end

      assert has_element?(view, "#seller p")
    end
  end

  test "related terms are grouped without breaking existing deep links", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/terms")

    assert has_element?(view, "#payment #invoices", "Payment is due as stated on the invoice.")
    assert has_element?(view, "#quality", "let me know as soon as possible and send a photo")
    assert has_element?(view, "#quality", "provided care instructions are followed")
    assert has_element?(view, ~s|#quality a[href="/en/faq#care"]|, "Read the care instructions")
    refute has_element?(view, "#quality", "within 3 days")
    refute has_element?(view, "#quality", "within 4 days")
    refute has_element?(view, "#quality a[href^=mailto]")
    refute has_element?(view, "#substitution")
    refute has_element?(view, ~s|a[href="#substitution"]|)
    assert has_element?(view, "#delivery #pickup", "during opening hours, unless we've agreed on another time")
    assert has_element?(view, "#delivery #delivery-problems", "a locked stairwell")

    days = Subscription.lead_days()
    assert has_element?(view, "#subscriptions #subscription-billing", "#{days} days before each delivery or pickup")
    assert has_element?(view, "#subscriptions #failed-payments", "the bouquet still comes")
    assert has_element?(view, "#subscriptions #failed-payments", "I'll get in touch with payment instructions")
    refute has_element?(view, "#subscriptions #failed-payments", "Nothing more is sent or charged")
    refute has_element?(view, "#payment", "before each bouquet")
  end

  test "delivery terms keep commitments and leave practical instructions to the FAQ", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/terms")

    assert has_element?(view, "#checkout-payments", "Subscriptions require a card.")

    assert has_element?(view, "#delivery-area", "There are no set delivery times.")
    refute has_element?(view, "#delivery", "The usual cutoff for same-day orders is midday.")
    refute has_element?(view, "#delivery", "choose a date at checkout")
    refute has_element?(view, "#delivery", "message when your order is ready")
    assert has_element?(view, "#unattended-delivery", "photo showing where I've left them")
    assert has_element?(view, ~s|#online-orders a[href="/account"]|, "Go to your account")
    assert has_element?(view, "#subscription-billing", "You pay for the first bouquet at checkout.")
    refute has_element?(view, "#delivery", "The earliest delivery is the next day")
  end

  test "names the payment processor but leaves card-data handling to privacy in every language", %{conn: conn} do
    for {path, privacy, statement, storage_detail} <- [
          {"/en/terms", "/en/privacy", "All payments on this website are processed by Stripe.", "security code"},
          {"/sv/kopvillkor", "/sv/privacy", "Alla betalningar på den här webbplatsen hanteras av Stripe.",
           "säkerhetskod"},
          {"/fi/toimitusehdot", "/fi/privacy", "Stripe käsittelee kaikki tämän verkkosivuston kautta tehtävät maksut.",
           "turvakoodia"}
        ] do
      {:ok, view, _html} = live(conn, path)

      assert has_element?(view, "#checkout-payments", statement)
      assert has_element?(view, ~s|#checkout-payments a[href="#{privacy}#sharing"]|)
      refute has_element?(view, "#checkout-payments", storage_detail)
    end
  end

  test "contact invitations use the contact page, with email only in seller details", %{conn: conn} do
    for {path, contact} <- [
          {"/en/terms", "/en/contact"},
          {"/sv/kopvillkor", "/sv/kontakt"},
          {"/fi/toimitusehdot", "/fi/yhteystiedot"}
        ] do
      {:ok, view, html} = live(conn, path)

      for section <- ["quality", "online-orders"] do
        assert has_element?(view, ~s|##{section} a[href="#{contact}"]|)
      end

      email_sections =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query("#main-content a[href^=mailto]")
        |> LazyHTML.attribute("href")

      assert email_sections == ["mailto:#{EdenflowersWeb.Business.email()}"]
      assert has_element?(view, "#seller a[href^=mailto]")
    end
  end

  test "only the contact phrase in the quality sentence is linked in each language", %{conn: conn} do
    for {path, contact, phrase, sentence} <- [
          {"/en/terms", "/en/contact", "let me know",
           "If your flowers arrive damaged or wilt early, let me know as soon as possible and send a photo."},
          {"/sv/kopvillkor", "/sv/kontakt", "hör av dig",
           "Om dina blommor kommer fram skadade eller vissnar i förtid, hör av dig så snart som möjligt och skicka en bild."},
          {"/fi/toimitusehdot", "/fi/yhteystiedot", "ilmoita minulle",
           "Jos kukkasi saapuvat vahingoittuneina tai kuihtuvat ennenaikaisesti, ilmoita minulle mahdollisimman pian ja lähetä kuva."}
        ] do
      {:ok, view, html} = live(conn, path)
      document = LazyHTML.from_document(html)

      assert has_element?(view, "#quality", sentence)
      assert document |> LazyHTML.query(~s|#quality a[href="#{contact}"]|) |> LazyHTML.text() == phrase
      refute html =~ "__CONTACT_LINK__"
    end
  end

  test "special booking cancellation terms are separate from online flower orders", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/terms")

    assert has_element?(view, "#cancellation #online-orders > h3", "Online flower orders")
    assert has_element?(view, ~s|#cancellation a[href="#weddings"]|, "Weddings")
    assert has_element?(view, ~s|#cancellation a[href="#courses"]|, "Courses")
    assert has_element?(view, "#wedding-cancellation", "not refunded if you cancel later than four weeks")
    assert has_element?(view, "#courses", "the cancellation terms on each course's page apply")
    refute has_element?(view, "#cancellation", "For courses, the cancellation terms")
  end

  test "service links and new headings are localized", %{conn: conn} do
    for page <- [
          %{
            path: "/en/terms",
            faq: "/en/faq",
            courses: "/en/courses",
            cancellation: "Changes and cancellations",
            seller: "Seller and contact details",
            quality: "Quality"
          },
          %{
            path: "/sv/kopvillkor",
            faq: "/sv/vanliga-fragor",
            courses: "/sv/kurser",
            cancellation: "Ändringar och avbokningar",
            seller: "Säljare och kontaktuppgifter",
            quality: "Kvalitet"
          },
          %{
            path: "/fi/toimitusehdot",
            faq: "/fi/ukk",
            courses: "/fi/kurssit",
            cancellation: "Muutokset ja peruutukset",
            seller: "Myyjä ja yhteystiedot",
            quality: "Laatu"
          }
        ] do
      {:ok, view, _html} = live(conn, page.path)

      assert has_element?(view, "#cancellation > h2", page.cancellation)
      assert has_element?(view, "#seller > h2", page.seller)
      assert has_element?(view, "#quality > h2", page.quality)
      assert has_element?(view, ~s|#quality a[href="#{page.faq}#care"]|)
      assert has_element?(view, ~s|#subscription-changes a[href="/account"]|)
      refute has_element?(view, ~s|#subscriptions a[href="#{page.faq}#subscriptions"]|)
      assert has_element?(view, ~s|#courses a[href="#{page.courses}"]|)
    end
  end

  test "purchase rules are complete in the terms in every language", %{conn: conn} do
    days = Subscription.change_deadline_days()

    for page <- [
          %{
            path: "/en/terms",
            substitution: "If a flower is out of season or unavailable, I use something similar of the same value.",
            deadline: "Make changes at least #{days} days before delivery or pickup.",
            late_cancellation: "Cancelling after that stops future bouquets, but the booked bouquet still comes.",
            pickup: "Collect your order during opening hours, unless we've agreed on another time.",
            wedding: "Half is invoiced as a booking fee about 4 weeks before the wedding, the rest afterwards."
          },
          %{
            path: "/sv/kopvillkor",
            substitution:
              "Om en blomma inte är i säsong eller inte finns att få tag på, använder jag något liknande av samma värde.",
            deadline: "Gör ändringar senast #{days} dagar före leverans eller avhämtning.",
            late_cancellation:
              "Om du avslutar prenumerationen efter det stoppas framtida buketter, men den redan bokade buketten kommer ändå.",
            pickup: "Hämta din beställning under öppettiderna, om vi inte har kommit överens om en annan tid.",
            wedding: "Hälften faktureras som bokningsavgift ungefär 4 veckor före bröllopet, resten efteråt."
          },
          %{
            path: "/fi/toimitusehdot",
            substitution: "Jos kukka ei ole sesongissa tai sitä ei saa, käytän jotain samankaltaista ja samanarvoista.",
            deadline: "Tee muutokset viimeistään #{days} päivää ennen toimitusta tai noutoa.",
            late_cancellation:
              "Jos lopetat kestotilauksen sen jälkeen, tulevat kimput peruuntuvat, mutta jo tilattu kimppu tulee silti.",
            pickup: "Nouda tilauksesi aukioloaikoina, ellei toisesta ajasta ole sovittu.",
            wedding: "Puolet laskutetaan varausmaksuna noin 4 viikkoa ennen häitä, loput jälkikäteen."
          }
        ] do
      {:ok, view, _html} = live(conn, page.path)

      assert has_element?(view, "#quality", page.substitution)
      assert has_element?(view, "#subscription-changes", page.deadline)
      assert has_element?(view, "#subscription-changes", page.late_cancellation)
      assert has_element?(view, ~s|#subscription-changes a[href="/account"]|)
      assert has_element?(view, "#pickup", page.pickup)
      assert has_element?(view, "#wedding-payment", page.wedding)
    end
  end

  test "leaves out the distance when nothing is delivered by distance", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/terms")

    assert has_element?(view, "#delivery", "I deliver on the day you choose at checkout.")
  end
end
