defmodule EdenflowersWeb.Marketing.WeddingsEstimateTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "the estimate sums the lowest prices and is carried into the enquiry email", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/weddings")

    assert view |> element("#wedding-estimate") |> render() =~ "110"

    view |> element(~s{[phx-value-item="bridesmaid_bouquet"][phx-value-by="1"]}) |> render_click()
    view |> element(~s{[phx-value-item="bridesmaid_bouquet"][phx-value-by="1"]}) |> render_click()
    view |> element(~s{[phx-value-item="cake_flowers"]}) |> render_click()

    assert view |> element("#wedding-estimate") |> render() =~ "200"
    assert render(view) =~ "+ cake flowers on request"

    # The estimate card and the enquiry section both link to the same email.
    [mailto] =
      view
      |> render()
      |> LazyHTML.from_document()
      |> LazyHTML.query("a[href^=mailto]")
      |> LazyHTML.attribute("href")
      |> Enum.uniq()

    body = mailto |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("body")

    assert body =~ "1 × Bridal bouquet"
    assert body =~ "2 × Bridesmaid's bouquet"
    assert body =~ "Cake flowers"
    assert body =~ "200"

    view |> element(~s{[phx-value-item="bridal_bouquet"][phx-value-by="-1"]}) |> render_click()
    assert view |> element("#wedding-estimate") |> render() =~ "90"
  end
end
