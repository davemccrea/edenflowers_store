defmodule EdenflowersWeb.Marketing.WeddingsEstimateTest do
  use EdenflowersWeb.ConnCase, async: true
  use Oban.Testing, repo: Edenflowers.Repo

  import Phoenix.LiveViewTest

  alias Edenflowers.WeddingEnquiry.SendEmails

  @enquiry %{"name" => "Anna Svensson", "email" => "anna@example.com", "wedding_date" => "2027-06-12"}

  test "the prices are hidden, so an enquiry goes without a selection", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/weddings")

    assert has_element?(view, ~s|a[href="#my-work"]|, "See my work")
    refute has_element?(view, ~s|a[href="#prices"]|)
    refute has_element?(view, "#wedding-estimate")

    view |> form("#enquiry-form", enquiry: @enquiry) |> render_submit()

    assert_enqueued(worker: SendEmails, args: %{name: "Anna Svensson", selection: []})
  end

  test "an enquiry queues the shop email and an acknowledgement that carry no typed text", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/weddings")

    typed = Map.merge(@enquiry, %{"venue" => "Zebrakulla", "message" => "Quokka please"})
    view |> form("#enquiry-form", enquiry: typed) |> render_submit()

    assert_enqueued(worker: SendEmails, args: %{name: "Anna Svensson", venue: "Zebrakulla"})
    assert_enqueued(worker: SendEmails, args: %{acknowledgement: true, email: "anna@example.com", locale: "en-GB"})

    [acknowledgement] = all_enqueued(worker: SendEmails) |> Enum.filter(& &1.args["acknowledgement"])
    assert Map.keys(acknowledgement.args) |> Enum.sort() == ["acknowledgement", "email", "locale"]
  end

  test "localized metadata describes the service without promising hidden prices", %{conn: conn} do
    for {path, expected} <- [
          {"/en/weddings",
           "Wedding flowers in Vaasa and Korsholm: bridal bouquets, decoration and flower arches designed by Jennie at Eden Flowers."},
          {"/sv/brollop",
           "Bröllopsblommor i Vasa och Korsholm: brudbuketter, dekoration och blomsterbågar som Jennie på Eden Flowers formger."},
          {"/fi/haat",
           "Hääkukat Vaasassa ja Mustasaaressa: hääkimput, koristelu ja kukkakaaret, jotka Jennie suunnittelee Eden Flowersissa."}
        ] do
      document = conn |> get(path) |> html_response(200) |> LazyHTML.from_document()

      assert document |> LazyHTML.query(~s(meta[name="description"])) |> LazyHTML.attribute("content") == [expected]
      assert document |> LazyHTML.query("#wedding-estimate") |> Enum.empty?()
    end
  end

  test "booking lead time and separately quoted travel are visible in every language", %{conn: conn} do
    for {path, lead_time, travel} <- [
          {"/en/weddings", "Most couples book 9–12 months ahead.",
           "I also provide wedding flowers outside Vaasa. Travel is quoted separately."},
          {"/sv/brollop", "De flesta par bokar 9–12 månader i förväg.",
           "Jag gör också bröllopsblommor utanför Vasa. Resan offereras separat."},
          {"/fi/haat", "Useimmat parit varaavat 9–12 kuukautta etukäteen.",
           "Teen hääkukkia myös Vaasan ulkopuolelle. Matkat hinnoittelen erikseen."}
        ] do
      {:ok, view, _html} = live(conn, path)

      assert has_element?(view, ~s(section[aria-labelledby="process-heading"]), lead_time)
      assert has_element?(view, "[aria-labelledby=enquire]", travel)
    end
  end

  @tag skip: "prices are hidden; unskip when @show_prices? is true again"
  test "the estimate sums the lowest prices and goes along with the enquiry", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/weddings")

    assert view |> element("#wedding-estimate") |> render() =~ "110 €–190 €"

    view |> element(~s{[phx-value-item="bridesmaid_bouquet"][phx-value-by="1"]}) |> render_click()
    view |> element(~s{[phx-value-item="bridesmaid_bouquet"][phx-value-by="1"]}) |> render_click()
    view |> element(~s{[phx-value-item="cake_flowers"]}) |> render_click()

    assert view |> element("#wedding-estimate") |> render() =~ "200 €–280 €"
    assert has_element?(view, "#estimate-cake-flowers")

    view |> form("#enquiry-form", enquiry: @enquiry) |> render_submit()

    assert has_element?(view, "#enquiry-sent")

    assert_enqueued(
      worker: SendEmails,
      args: %{
        name: "Anna Svensson",
        selection: ["1 × Bridal bouquet", "2 × Bridesmaid's bouquet", "Cake flowers"],
        estimate: "200 €–280 €"
      }
    )
  end

  test "an enquiry without a wedding date isn't sent", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/weddings")

    view |> form("#enquiry-form", enquiry: Map.delete(@enquiry, "wedding_date")) |> render_submit()

    refute has_element?(view, "#enquiry-sent")
    refute_enqueued(worker: SendEmails)
  end

  test "an over-long message isn't sent", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/weddings")

    html =
      view
      |> form("#enquiry-form", enquiry: Map.put(@enquiry, "message", String.duplicate("a", 5001)))
      |> render_submit()

    assert html =~ "Should be at most 5000 characters"
    refute has_element?(view, "#enquiry-sent")
    refute_enqueued(worker: SendEmails)
  end

  test "a filled-in honeypot looks sent but nothing goes out", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/weddings")

    view |> form("#enquiry-form", enquiry: @enquiry) |> render_submit(%{enquiry: %{website: "spam.example"}})

    assert has_element?(view, "#enquiry-sent")
    refute_enqueued(worker: SendEmails)
  end

  test "a visitor's sixth enquiry within the hour queues nothing, while another visitor still gets through", %{
    conn: conn
  } do
    busy = %{conn | remote_ip: {10, 30, 0, 1}}

    for _ <- 1..5 do
      {:ok, view, _html} = live(busy, ~p"/en/weddings")
      view |> form("#enquiry-form", enquiry: @enquiry) |> render_submit()
      assert has_element?(view, "#enquiry-sent")
    end

    {:ok, view, _html} = live(busy, ~p"/en/weddings")
    html = view |> form("#enquiry-form", enquiry: @enquiry) |> render_submit()

    refute has_element?(view, "#enquiry-sent")
    assert html =~ "Too many requests"
    assert length(all_enqueued(worker: SendEmails)) == 10

    {:ok, view, _html} = live(%{conn | remote_ip: {10, 30, 0, 2}}, ~p"/en/weddings")
    view |> form("#enquiry-form", enquiry: @enquiry) |> render_submit()
    assert has_element?(view, "#enquiry-sent")
  end
end
