defmodule EdenflowersWeb.Marketing.FaqLiveTest do
  use EdenflowersWeb.ConnCase, async: false

  import Generator
  import Phoenix.LiveViewTest
  import Mox

  alias Edenflowers.Orders.Subscription

  setup :verify_on_exit!

  test "uses the reference-page typography without an update notice", %{conn: conn} do
    for path <- ["/en/faq", "/sv/vanliga-fragor", "/fi/ukk"] do
      {:ok, view, _html} = live(conn, path)

      assert has_element?(view, "#main-content h1.font-sans.font-semibold")
      assert has_element?(view, "#faq-nav .category-index__name.font-sans.text-sm")
      assert has_element?(view, "#faq-questions section > h2.font-sans.font-semibold")
      assert has_element?(view, "#ask-heading.font-sans.font-semibold")
      assert has_element?(view, "#faq-questions .collapse-content.text-base-content.font-normal.leading-relaxed")
      refute has_element?(view, "#main-content .page-title, #main-content .section-title, #faq-nav .font-serif")
      refute has_element?(view, "#faq-questions .collapse-content[class*=\"text-base-content/80\"]")
      refute has_element?(view, "#notice-updated")
    end
  end

  test "answers expand individually without a toggle-all button in every storefront language", %{conn: conn} do
    for path <- ["/en/faq", "/sv/vanliga-fragor", "/fi/ukk"] do
      {:ok, view, _html} = live(conn, path)

      assert has_element?(view, "#faq-questions details summary")
      refute has_element?(view, "#faq-questions details[open]")
      refute has_element?(view, "#faq-toggle-all")
    end
  end

  test "the card answer explains checkout without listing message limits", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/faq")

    assert has_element?(view, "#ordering details", "Choose a card at checkout and write your message.")
    refute has_element?(view, "#ordering", "characters")
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
             "Within 17 km driving distance of the shop, for 5,00 € plus 1,20 € per km"
           )

    assert has_element?(view, "#delivery details", "delivered free within 4 km")
  end

  test "the cancel answer gives the change deadline and links the terms", %{conn: conn} do
    days = Subscription.change_deadline_days()

    {:ok, view, _html} = live(conn, ~p"/en/faq")

    assert has_element?(view, "#ordering details", "until #{days} days before delivery or pickup")
    assert has_element?(view, ~s|#ordering a[href="/account"]|, "from your account")
    assert has_element?(view, ~s|#ordering a[href="/en/terms#cancellation"]|)
    assert has_element?(view, ~s|#ordering-question-2 a[href="/en/contact"]|, "get in touch")
    refute has_element?(view, "#ordering", "I'm usually flexible.")
  end

  test "seasonality and damaged flower answers both link to the quality terms", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/faq")

    assert has_element?(view, "#care-question-1", "I use local and seasonal flowers whenever possible.")
    refute has_element?(view, "#care-question-1", "something similar of the same value")
    assert has_element?(view, ~s|#care-question-1 a[href="/en/terms#quality"]|)
    assert has_element?(view, ~s|#care-question-2 a[href="/en/terms#quality"]|)
    refute has_element?(view, ~s|a[href="/en/terms#substitution"]|)
  end

  test "flower care has four practical points and the same quality conditions as the terms", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/en/faq")

    care_points =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("#care ul li")
      |> Enum.map(&LazyHTML.text/1)

    assert length(care_points) == 4
    assert Enum.at(care_points, 0) == "Use a clean vase with fresh water."
    assert Enum.at(care_points, 1) =~ "leaves that would sit below the waterline"
    assert Enum.at(care_points, 2) =~ "Change the water and re-cut the stems every 2–3 days"
    assert Enum.at(care_points, 3) =~ "heat sources and ripe fruit"
    refute has_element?(view, "#care", "cut-flower food")
    refute has_element?(view, "#care", "sharp, clean knife or secateurs")
    assert has_element?(view, "#care details", "A lot depends on the flowers, but typically around 7–10 days.")
    assert has_element?(view, "#care details", "Let me know as soon as possible and send a photo.")
    assert has_element?(view, "#care details", "provided care instructions are followed")
    refute has_element?(view, "#care", "within 3 days")
    refute has_element?(view, "#care", "5–7 days")
  end

  test "answer links are phrases within prose rather than standalone link paragraphs", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/en/faq")
    document = LazyHTML.from_document(html)

    paragraphs = LazyHTML.query(document, "#faq-questions .collapse-content p")
    linked_paragraphs = Enum.reject(paragraphs, &Enum.empty?(LazyHTML.query(&1, "a")))
    assert length(linked_paragraphs) >= 10

    for paragraph <- linked_paragraphs do
      linked_text = paragraph |> LazyHTML.query("a") |> Enum.map_join(" ", &LazyHTML.text/1)
      prose = paragraph |> LazyHTML.text() |> String.replace(~r/\s+/, " ") |> String.trim()
      assert String.length(prose) > String.length(linked_text)
    end

    assert has_element?(view, ~s|#ordering-question-2 p a[href="/account"]|, "from your account")
    refute has_element?(view, "#faq-questions", "See the quality terms")
    refute has_element?(view, "#faq-questions", "Go to your account")
    assert has_element?(view, "#subscriptions > div > p", "Your subscription is covered by our")
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
    assert text =~ "from your account"
    assert text =~ "cancellation terms."
    refute text =~ "<"

    assert Enum.any?(questions, &(&1["name"] == "When do I pay?"))
    assert length(questions) == 21
    refute Enum.any?(questions, &(&1["name"] == "What's included in a course, and what should I bring?"))

    care = Enum.find(questions, &(&1["name"] == "How long will my flowers last, and how should I care for them?"))
    assert care["acceptedAnswer"]["text"] =~ "Use a clean vase with fresh water."
    assert care["acceptedAnswer"]["text"] =~ "heat sources and ripe fruit."
    refute care["acceptedAnswer"]["text"] =~ "cut-flower food"
    refute care["acceptedAnswer"]["text"] =~ "sharp, clean knife or secateurs"
  end

  test "delivery and pickup dates depend on the chosen products, with midday only a usual cutoff", %{conn: conn} do
    Generator.shop_calendar(same_day: true, order_deadline: ~T[11:30:00])

    {:ok, view, _html} = live(conn, ~p"/en/faq")

    assert has_element?(
             view,
             "#delivery",
             "Checkout shows the available delivery and pickup dates for the products you choose."
           )

    assert has_element?(view, "#delivery", "The usual cutoff for same-day orders is midday.")
    assert has_element?(view, "#delivery-question-0", "There are no set delivery times.")
    refute has_element?(view, "#delivery", "order by 11:30")
  end

  test "subscription answers explain free pickup, cancellation and payment instructions", %{conn: conn} do
    generate(
      fulfillment_option(
        fulfillment_method: :delivery,
        rate_type: :dynamic,
        free_dist_km: 4,
        base_price: "5.00",
        price_per_km: "1.20"
      )
    )

    {:ok, view, _html} = live(conn, ~p"/en/faq")

    assert has_element?(view, "#subscriptions", "Can I collect my subscription bouquets?")
    assert has_element?(view, "#subscriptions", "Pickup is always free.")
    refute has_element?(view, "#subscriptions", "per km")
    refute has_element?(view, "#subscriptions", "Delivery is free within")
    assert has_element?(view, "#subscriptions", "#{Subscription.lead_days()} days before each delivery or pickup")

    assert has_element?(
             view,
             "#subscriptions",
             "Make changes at least #{Subscription.change_deadline_days()} days before"
           )

    assert has_element?(
             view,
             "#subscriptions",
             "Cancelling after that stops future bouquets, but the booked bouquet still comes."
           )

    assert has_element?(view, "#subscriptions", "I'll get in touch with payment instructions.")
    refute has_element?(view, "#subscriptions", "Nothing more is sent or charged")
  end

  test "linked answers form complete translated sentences", %{conn: conn} do
    for {path, delivery, quality, wedding} <- [
          {"/sv/vanliga-fragor", "Om jag inte kommer in förklarar våra leveransvillkor vad som händer sedan.",
           "Våra kvalitetsvillkor beskriver villkoren.", "Din bokning följer våra bröllopsvillkor."},
          {"/fi/ukk", "Jos en pääse sisään, toimitusehdoissa kerrotaan, mitä seuraavaksi tapahtuu.",
           "Meidän laatuehtomme kertovat tarkemmat ehdot.", "Varaukseesi sovelletaan hääkukkien ehtoja."}
        ] do
      {:ok, _view, html} = live(conn, path)
      document = LazyHTML.from_document(html)

      for {section, sentence} <- [{"delivery", delivery}, {"care", quality}, {"weddings", wedding}] do
        text = document |> LazyHTML.query("##{section}") |> LazyHTML.text() |> String.replace(~r/\s+/, " ")
        assert text =~ sentence
      end
    end
  end

  test "practical answers cover pickup, delivery notifications and payment exceptions", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/faq")

    assert has_element?(view, "#delivery summary", "Do you deliver to the hospital?")
    assert has_element?(view, "#delivery", "photo showing where I've left them")
    assert has_element?(view, "#delivery", "If you're sending a gift, you receive an email when it's delivered.")
    assert has_element?(view, "#delivery", "Choose your pickup date at checkout.")
    assert has_element?(view, "#ordering summary", "isn't in the online shop?")
    assert has_element?(view, "#payment", "Subscriptions require a card.")
    assert has_element?(view, "#payment", "I also offer invoice payment for larger orders")
    assert has_element?(view, "#weddings", "Saturdays in particular fill up quickly")
    assert has_element?(view, "#weddings", "a limited number of weddings each Saturday")
    assert has_element?(view, "#weddings", "Most couples book 9–12 months ahead.")
    assert has_element?(view, ~s|#weddings a[href="/en/contact"]|, "get in touch")
    assert has_element?(view, "#weddings summary", "Do you provide wedding flowers outside Vaasa?")
    refute has_element?(view, ~s|#weddings a[href="/en/weddings"]|)
    assert has_element?(view, "#courses", "deadline for a full refund and the cancellation fee after that")
    refute has_element?(view, "#courses summary", "what should I bring?")
  end

  test "purchase rule summaries link to localized terms", %{conn: conn} do
    for {faq, terms, timing} <- [
          {"/en/faq", "/en/terms", "There are no set delivery times."},
          {"/sv/vanliga-fragor", "/sv/kopvillkor", "Det finns inga fasta leveranstider."},
          {"/fi/ukk", "/fi/toimitusehdot", "Tarkkoja toimitusaikoja ei ole."}
        ] do
      {:ok, view, _html} = live(conn, faq)

      assert has_element?(view, "#delivery-question-0", timing)
      assert has_element?(view, ~s|#care-question-1 a[href="#{terms}#quality"]|)
      assert has_element?(view, ~s|#subscriptions a[href="#{terms}#subscriptions"]|)
      assert has_element?(view, ~s|#weddings-question-2 a[href="#{terms}#weddings"]|)
    end
  end

  test "all invitations to contact Jennie link to the contact page", %{conn: conn} do
    for {path, contact} <- [
          {"/en/faq", "/en/contact"},
          {"/sv/vanliga-fragor", "/sv/kontakt"},
          {"/fi/ukk", "/fi/yhteystiedot"}
        ] do
      {:ok, view, _html} = live(conn, path)

      for question <- [
            "delivery-question-3",
            "ordering-question-0",
            "ordering-question-2",
            "care-question-2",
            "payment-question-1",
            "weddings-question-0"
          ] do
        assert has_element?(view, ~s|##{question} a[href="#{contact}"]|)
      end

      assert has_element?(view, ~s|section[aria-labelledby=ask-heading] a[href="#{contact}"]|)
      refute has_element?(view, "#main-content a[href^=mailto]")
    end
  end

  test "unchanged answers remain localized in Swedish and Finnish", %{conn: conn} do
    for page <- [
          %{
            path: "/sv/vanliga-fragor",
            hospital: "Levererar du till sjukhuset?",
            care: "Det beror mycket på blommorna, men vanligtvis håller de i ungefär 7–10 dagar.",
            payment: "Prenumerationer kräver kortbetalning.",
            subscription: "Kan jag pausa eller avsluta min prenumeration?",
            pickup: "Ja, välj avhämtning i kassan."
          },
          %{
            path: "/fi/ukk",
            hospital: "Toimitatko Vaasan sairaalaan?",
            care: "Kestävyys riippuu paljon kukista, mutta yleensä ne kestävät noin 7–10 päivää.",
            payment: "Kestotilaukset edellyttävät korttimaksua.",
            subscription: "Voinko pitää tauon kestotilauksestani tai lopettaa sen?",
            pickup: "Kyllä, valitse kassalla nouto."
          }
        ] do
      {:ok, view, _html} = live(conn, page.path)

      assert has_element?(view, "#delivery summary", page.hospital)
      assert has_element?(view, "#care", page.care)
      assert has_element?(view, "#payment", page.payment)
      assert has_element?(view, "#subscriptions summary", page.subscription)
      assert has_element?(view, "#subscriptions", page.pickup)
    end
  end

  describe "delivery cost checker" do
    setup do
      option =
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

      %{delivery_option: option}
    end

    test "pricing precedes the checkout-sized checker with lookup on blur", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/en/faq")

      assert has_element?(
               view,
               "#delivery-question-0 > div > p:first-child",
               "1,20 € per km. Some products, like subscriptions, are delivered free within 4 km."
             )

      assert has_element?(
               view,
               "#delivery-question-0 > div > p:first-child + p",
               "Enter an address below to check the delivery distance and price."
             )

      assert has_element?(view, "#delivery-question-0 > div > p:first-child + p + div #faq-delivery-cost")
      assert has_element?(view, ~s|#address-input-field[aria-label="Check delivery distance and price"]|)
      assert has_element?(view, ~s|#address-input-field[placeholder="Myrvägen 1, 65230 Vasa"]|)
      assert has_element?(view, "#address-input-field.input-lg.w-full.text-base")
      assert has_element?(view, ~s|#address-input-field[phx-blur="lookup_address"]|)
      refute has_element?(view, "#faq-delivery-cost label > span")
      refute has_element?(view, "#faq-delivery-cost button")
      refute has_element?(view, "#faq-delivery-cost.max-w-sm")

      assert has_element?(view, "#delivery-question-0.overflow-visible")

      [mounted] =
        html |> LazyHTML.from_document() |> LazyHTML.query("#delivery-question-0") |> LazyHTML.attribute("phx-mounted")

      assert [["ignore_attrs", %{"attrs" => ["open"]}]] = Jason.decode!(mounted)
    end

    test "quotes the driving-distance price when tabbing out of the address", %{conn: conn} do
      expect(Edenflowers.External.HereAPI.Mock, :geocode, fn "Stadsgatan 3" ->
        {:ok, {"Stadsgatan 3, 65300 Vasa", "63.0951,21.6165", "here-id-123"}}
      end)

      expect(Edenflowers.External.HereAPI.Mock, :route_distance, fn "63.0951,21.6165" -> {:ok, 8000} end)

      {:ok, view, _html} = live(conn, ~p"/en/faq")
      refute has_element?(view, "[data-testid=faq-delivery-quote]", "Delivery:")

      view |> element("#address-input-field") |> render_blur(%{"value" => "Stadsgatan 3"})
      render_async(view, 1000)

      assert has_element?(view, "[data-testid=faq-delivery-quote] > p.text-success", "Delivery: 14,60 €")
      refute has_element?(view, "[data-testid=address-confirmation]")
      refute has_element?(view, "[data-testid=faq-delivery-quote]", "delivered free to this address")

      view |> element("#address-input-field") |> render_change(%{"delivery_address" => "Another address"})

      refute has_element?(view, "[data-testid=faq-delivery-quote]", "Delivery:")
      refute has_element?(view, "[data-testid=address-confirmation]")
    end

    test "shows only the ordinary fee inside the free-delivery area", %{conn: conn} do
      expect(Edenflowers.External.HereAPI.Mock, :geocode, fn _address ->
        {:ok, {"Stadsgatan 3, 65300 Vasa", "63.0951,21.6165", "here-id-123"}}
      end)

      expect(Edenflowers.External.HereAPI.Mock, :route_distance, fn _position -> {:ok, 3000} end)

      {:ok, view, _html} = live(conn, ~p"/en/faq")
      view |> element("#faq-delivery-cost") |> render_submit(%{"delivery_address" => "Stadsgatan 3"})
      render_async(view, 1000)

      assert has_element?(view, "[data-testid=faq-delivery-quote]", "Delivery: 8,60 €")
      assert has_element?(view, "[data-testid=faq-delivery-quote] > p:only-child", "Delivery: 8,60 €")
      refute has_element?(view, "[data-testid=faq-delivery-quote]", "Products marked for free delivery")
    end

    test "the checker and availability guidance use the customer's language", %{conn: conn} do
      test_pid = self()

      expect(Edenflowers.External.HereAPI.Mock, :geocode, 2, fn _address ->
        send(test_pid, {:lookup_locale, Gettext.get_locale(EdenflowersWeb.Gettext)})
        {:ok, {"Stadsgatan 3, 65300 Vasa", "63.0951,21.6165", "here-id-123"}}
      end)

      expect(Edenflowers.External.HereAPI.Mock, :route_distance, 2, fn _position -> {:ok, 3000} end)

      for {path, locale, availability, price, free} <- [
            {"/sv/vanliga-fragor", "sv",
             "I kassan ser du vilka leverans- och avhämtningsdatum som är möjliga för produkterna du väljer.",
             "Leverans:", "levereras gratis till den här adressen"},
            {"/fi/ukk", "fi", "Kassalla näet valitsemillesi tuotteille saatavilla olevat toimitus- ja noutopäivät.",
             "Toimitus:", "toimitetaan tähän osoitteeseen ilmaiseksi"}
          ] do
        {:ok, view, _html} = live(conn, path)

        refute has_element?(view, "#faq-delivery-cost button")
        assert has_element?(view, "#delivery", availability)

        view |> element("#faq-delivery-cost") |> render_submit(%{"delivery_address" => "Stadsgatan 3"})
        render_async(view, 1000)

        assert_receive {:lookup_locale, ^locale}
        assert has_element?(view, "[data-testid=faq-delivery-quote]", price)
        refute has_element?(view, "[data-testid=faq-delivery-quote]", free)
      end
    end

    test "an address beyond the delivery area shows no price", %{conn: conn} do
      expect(Edenflowers.External.HereAPI.Mock, :geocode, fn _address ->
        {:ok, {"Far Away 1", "63.0951,21.6165", "here-id-123"}}
      end)

      expect(Edenflowers.External.HereAPI.Mock, :route_distance, fn _position -> {:ok, 20_000} end)

      {:ok, view, _html} = live(conn, ~p"/en/faq")
      view |> element("#faq-delivery-cost") |> render_submit(%{"delivery_address" => "Far Away 1"})
      render_async(view, 1000)

      assert has_element?(view, "#faq-delivery-cost", "Outside delivery range")
      refute has_element?(view, "[data-testid=faq-delivery-quote]", "Delivery:")
    end

    test "failed lookups clear a previous price", %{conn: conn} do
      expect(Edenflowers.External.HereAPI.Mock, :geocode, fn "Stadsgatan 3" ->
        {:ok, {"Stadsgatan 3, 65300 Vasa", "63.0951,21.6165", "here-id-123"}}
      end)

      expect(Edenflowers.External.HereAPI.Mock, :route_distance, fn _position -> {:ok, 8000} end)
      expect(Edenflowers.External.HereAPI.Mock, :geocode, fn "Unknown address" -> {:error, :address_not_found} end)

      {:ok, view, _html} = live(conn, ~p"/en/faq")
      view |> element("#faq-delivery-cost") |> render_submit(%{"delivery_address" => "Stadsgatan 3"})
      render_async(view, 1000)
      assert has_element?(view, "[data-testid=faq-delivery-quote]", "Delivery: 14,60 €")

      view |> element("#faq-delivery-cost") |> render_submit(%{"delivery_address" => "Unknown address"})
      render_async(view, 1000)

      assert has_element?(view, "#faq-delivery-cost", "Address not found")
      refute has_element?(view, "[data-testid=faq-delivery-quote]", "Delivery:")
    end

    test "a routing service failure shows a retry message instead of a price", %{conn: conn} do
      expect(Edenflowers.External.HereAPI.Mock, :geocode, fn _address ->
        {:ok, {"Stadsgatan 3, 65300 Vasa", "63.0951,21.6165", "here-id-123"}}
      end)

      expect(Edenflowers.External.HereAPI.Mock, :route_distance, fn _position -> {:error, :timeout} end)

      {:ok, view, _html} = live(conn, ~p"/en/faq")
      view |> element("#faq-delivery-cost") |> render_submit(%{"delivery_address" => "Stadsgatan 3"})
      render_async(view, 1000)

      assert has_element?(view, "#faq-delivery-cost", "please try again later")
      refute has_element?(view, "[data-testid=faq-delivery-quote]", "Delivery:")
    end

    test "tabbing past an empty checker does not show a required-field error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/faq")

      view |> element("#address-input-field") |> render_blur(%{"value" => ""})
      refute has_element?(view, "#faq-delivery-cost", "This field is required")
      assert has_element?(view, ~s|#address-input-field[aria-required="false"]|)

      for address <- ["", "   "] do
        view |> element("#address-input-field") |> render_change(%{"delivery_address" => address})
        refute has_element?(view, "#faq-delivery-cost", "This field is required")

        view |> element("#address-input-field") |> render_blur(%{"value" => address})

        refute has_element?(view, "#faq-delivery-cost", "This field is required")
        refute has_element?(view, ~s|#address-input-field[aria-invalid="true"]|)
        refute has_element?(view, "[data-testid=faq-delivery-quote]", "Delivery:")
      end
    end

    test "an empty address is required before a price can be checked", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/en/faq")
      view |> element("#faq-delivery-cost") |> render_submit(%{"delivery_address" => ""})

      assert has_element?(view, "#faq-delivery-cost", "This field is required")
      refute has_element?(view, "[data-testid=faq-delivery-quote]", "Delivery:")
    end

    test "typing a different address cancels an unfinished lookup", %{conn: conn} do
      test_pid = self()

      expect(Edenflowers.External.HereAPI.Mock, :geocode, fn _address ->
        send(test_pid, :lookup_started)

        receive do
          :finish -> {:ok, {"Old address", "63.0951,21.6165", "here-id-123"}}
        end
      end)

      {:ok, view, _html} = live(conn, ~p"/en/faq")
      view |> element("#faq-delivery-cost") |> render_submit(%{"delivery_address" => "Old address"})
      assert_receive :lookup_started

      view |> element("#address-input-field") |> render_change(%{"delivery_address" => "New address"})
      render_async(view, 1000)

      refute has_element?(view, "[data-testid=faq-delivery-quote]", "Delivery:")
      refute has_element?(view, "[data-testid=address-confirmation]")
      refute has_element?(view, "#faq-delivery-cost", "problem calculating")
    end
  end

  test "no address checker is shown without distance-priced delivery", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/faq")

    refute has_element?(view, "#faq-delivery-cost")
    assert has_element?(view, "#delivery", "Enter the address at checkout")
  end

  test "the delivery answer does not promise next-day delivery when same day is off", %{conn: conn} do
    Generator.shop_calendar(same_day: false)

    {:ok, view, _html} = live(conn, ~p"/en/faq")

    assert has_element?(
             view,
             "#delivery",
             "Checkout shows the available delivery and pickup dates for the products you choose."
           )

    refute has_element?(view, "#delivery", "The earliest delivery is the next day the shop is open.")
  end
end
