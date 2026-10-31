defmodule EdenflowersWeb.Marketing.TermsLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  alias Edenflowers.Orders.Subscription

  test "shows the last-updated date", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/terms")

    assert has_element?(view, "#main-content #notice-updated", "Updated 26 October 2026.")
  end

  test "reads the delivery distance and cancellation deadline live", %{conn: conn} do
    generate(fulfillment_option(fulfillment_method: :delivery, rate_type: :dynamic, max_dist_km: 17))
    days = Subscription.change_deadline_days()

    {:ok, view, _html} = live(conn, ~p"/en/terms")

    assert has_element?(view, "[aria-labelledby=delivery]", "I deliver within 17 km driving distance of the shop")
    assert has_element?(view, "[aria-labelledby=cancellation]", "until #{days} days before delivery or pickup")
    assert has_element?(view, "[aria-labelledby=seller]", EdenflowersWeb.Business.business_id())
  end

  test "related terms are grouped without breaking existing deep links", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/terms")

    assert has_element?(
             view,
             "[aria-labelledby=payment] [aria-labelledby=invoices]",
             "Payment is due as stated on the invoice."
           )

    assert has_element?(view, "[aria-labelledby=quality]", "let me know as soon as possible and send a photo")
    assert has_element?(view, "[aria-labelledby=quality]", "provided care instructions are followed")
    assert has_element?(view, ~s|[aria-labelledby=quality] a[href="/en/faq#care"]|, "Read the care instructions")
    refute has_element?(view, "[aria-labelledby=quality]", "within 3 days")
    refute has_element?(view, "[aria-labelledby=quality]", "within 4 days")
    refute has_element?(view, "[aria-labelledby=quality] a[href^=mailto]")
    refute has_element?(view, "#substitution")
    refute has_element?(view, ~s|a[href="#substitution"]|)

    assert has_element?(
             view,
             "[aria-labelledby=delivery] [aria-labelledby=pickup]",
             "during opening hours, unless we've agreed on another time"
           )

    assert has_element?(view, "[aria-labelledby=delivery] [aria-labelledby=delivery-problems]", "a locked stairwell")

    days = Subscription.lead_days()

    assert has_element?(
             view,
             "[aria-labelledby=subscriptions] [aria-labelledby=subscription-billing]",
             "#{days} days before each delivery or pickup"
           )

    assert has_element?(
             view,
             "[aria-labelledby=subscriptions] [aria-labelledby=failed-payments]",
             "the bouquet still comes"
           )

    assert has_element?(
             view,
             "[aria-labelledby=subscriptions] [aria-labelledby=failed-payments]",
             "I'll get in touch with payment instructions"
           )

    refute has_element?(
             view,
             "[aria-labelledby=subscriptions] [aria-labelledby=failed-payments]",
             "Nothing more is sent or charged"
           )

    refute has_element?(view, "[aria-labelledby=payment]", "before each bouquet")
  end

  test "delivery terms keep commitments and leave practical instructions to the FAQ", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/terms")

    assert has_element?(view, "[aria-labelledby=checkout-payments]", "Subscriptions require a card.")

    assert has_element?(view, "[aria-labelledby=delivery-area]", "There are no set delivery times.")
    refute has_element?(view, "[aria-labelledby=delivery]", "The usual cutoff for same-day orders is midday.")
    assert has_element?(view, "[aria-labelledby=unattended-delivery]", "photo showing where I've left them")
    assert has_element?(view, ~s|[aria-labelledby=online-orders] a[href="/account"]|, "Go to your account")
    assert has_element?(view, "[aria-labelledby=subscription-billing]", "You pay for the first bouquet at checkout.")
    refute has_element?(view, "[aria-labelledby=delivery]", "The earliest delivery is the next day")
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

      assert has_element?(view, "[aria-labelledby=checkout-payments]", statement)
      assert has_element?(view, ~s|[aria-labelledby=checkout-payments] a[href="#{privacy}#sharing"]|)
      refute has_element?(view, "[aria-labelledby=checkout-payments]", storage_detail)
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
        assert has_element?(view, ~s|[aria-labelledby=#{section}] a[href="#{contact}"]|)
      end

      email_sections =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query("#main-content a[href^=mailto]")
        |> LazyHTML.attribute("href")

      assert email_sections == ["mailto:#{EdenflowersWeb.Business.email()}"]
      assert has_element?(view, "[aria-labelledby=seller] a[href^=mailto]")
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

      assert has_element?(view, "[aria-labelledby=quality]", sentence)
      assert document |> LazyHTML.query(~s|[aria-labelledby=quality] a[href="#{contact}"]|) |> LazyHTML.text() == phrase
      refute html =~ "__CONTACT_LINK__"
    end
  end

  test "special booking cancellation terms are separate from online flower orders", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/terms")

    assert has_element?(
             view,
             "[aria-labelledby=cancellation] [aria-labelledby=online-orders] > h3",
             "Online flower orders"
           )

    assert has_element?(view, ~s|[aria-labelledby=cancellation] a[href="#weddings"]|, "Weddings")
    assert has_element?(view, ~s|[aria-labelledby=cancellation] a[href="#courses"]|, "Courses")

    assert has_element?(
             view,
             "[aria-labelledby=wedding-cancellation]",
             "not refunded if you cancel later than four weeks"
           )

    assert has_element?(view, "[aria-labelledby=courses]", "the cancellation terms on each course's page apply")
    refute has_element?(view, "[aria-labelledby=cancellation]", "For courses, the cancellation terms")
  end

  test "service links use localized routes", %{conn: conn} do
    for {path, faq, courses} <- [
          {"/en/terms", "/en/faq", "/en/courses"},
          {"/sv/kopvillkor", "/sv/vanliga-fragor", "/sv/kurser"},
          {"/fi/toimitusehdot", "/fi/ukk", "/fi/kurssit"}
        ] do
      {:ok, view, _html} = live(conn, path)

      assert has_element?(view, ~s|[aria-labelledby=quality] a[href="#{faq}#care"]|)
      assert has_element?(view, ~s|[aria-labelledby=subscription-changes] a[href="/account"]|)
      refute has_element?(view, ~s|[aria-labelledby=subscriptions] a[href="#{faq}#subscriptions"]|)
      assert has_element?(view, ~s|[aria-labelledby=courses] a[href="#{courses}"]|)
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

      assert has_element?(view, "[aria-labelledby=quality]", page.substitution)
      assert has_element?(view, "[aria-labelledby=subscription-changes]", page.deadline)
      assert has_element?(view, "[aria-labelledby=subscription-changes]", page.late_cancellation)
      assert has_element?(view, ~s|[aria-labelledby=subscription-changes] a[href="/account"]|)
      assert has_element?(view, "[aria-labelledby=pickup]", page.pickup)
      assert has_element?(view, "[aria-labelledby=wedding-payment]", page.wedding)
    end
  end

  test "leaves out the distance when nothing is delivered by distance", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/terms")

    assert has_element?(view, "[aria-labelledby=delivery]", "I deliver on the day you choose at checkout.")
  end
end
