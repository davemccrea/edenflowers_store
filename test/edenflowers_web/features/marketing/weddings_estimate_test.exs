defmodule EdenflowersWeb.Marketing.WeddingsEstimateTest do
  use EdenflowersWeb.ConnCase, async: true
  use Oban.Testing, repo: Edenflowers.Repo

  import Phoenix.LiveViewTest

  alias Edenflowers.WeddingEnquiry.SendEmails

  @enquiry %{"name" => "Anna Svensson", "email" => "anna@example.com", "wedding_date" => "2027-06-12"}

  test "the estimate sums the lowest prices and goes along with the enquiry", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/weddings")

    assert view |> element("#wedding-estimate") |> render() =~ "€110–€190"

    view |> element(~s{[phx-value-item="bridesmaid_bouquet"][phx-value-by="1"]}) |> render_click()
    view |> element(~s{[phx-value-item="bridesmaid_bouquet"][phx-value-by="1"]}) |> render_click()
    view |> element(~s{[phx-value-item="cake_flowers"]}) |> render_click()

    assert view |> element("#wedding-estimate") |> render() =~ "€200–€280"
    assert has_element?(view, "#estimate-cake-flowers")

    view |> form("#enquiry-form", enquiry: @enquiry) |> render_submit()

    assert has_element?(view, "#enquiry-sent")

    assert_enqueued(
      worker: SendEmails,
      args: %{
        name: "Anna Svensson",
        selection: ["1 × Bridal bouquet", "2 × Bridesmaid's bouquet", "Cake flowers"],
        estimate: "€200–€280"
      }
    )
  end

  test "an enquiry without a wedding date isn't sent", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/weddings")

    view |> form("#enquiry-form", enquiry: Map.delete(@enquiry, "wedding_date")) |> render_submit()

    refute has_element?(view, "#enquiry-sent")
    refute_enqueued(worker: SendEmails)
  end

  test "a filled-in honeypot looks sent but nothing goes out", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/weddings")

    view |> form("#enquiry-form", enquiry: @enquiry) |> render_submit(%{enquiry: %{website: "spam.example"}})

    assert has_element?(view, "#enquiry-sent")
    refute_enqueued(worker: SendEmails)
  end
end
