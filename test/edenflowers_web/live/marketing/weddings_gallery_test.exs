defmodule EdenflowersWeb.Marketing.WeddingsGalleryTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/weddings")
    %{html: html}
  end

  test "each gallery link requests the exact size it tells PhotoSwipe to expect", %{html: html} do
    links =
      Regex.scan(
        ~r/<a[^>]*href="([^"]+)"[^>]*data-pswp-width="(\d+)"[^>]*data-pswp-height="(\d+)"/,
        html
      )

    assert length(links) == 3

    for [_, href, declared_width, declared_height] <- links do
      # Pull the dimensions back out of the Imgproxy URL rather than trusting
      # the assign both sides came from — PhotoSwipe zooms against the declared
      # size, so a resize option that caps or crops differently breaks zooming.
      assert [_, requested_width, requested_height] =
               Regex.run(~r/rs:fill:(\d+):(\d+)/, href)

      assert requested_width == declared_width
      assert requested_height == declared_height
    end
  end

  test "a credit renders both as a caption and as the attribute the hook reads", %{html: html} do
    captions = Regex.scan(~r/<figcaption[^>]*>\s*([^<]+?)\s*<\/figcaption>/, html)
    attributes = Regex.scan(~r/data-pswp-credit="([^"]+)"/, html)

    # The lightbox credit and the visible caption must come from the same
    # source — if they drift, the photographer gets credited in only one place.
    assert Enum.map(captions, &Enum.at(&1, 1)) == Enum.map(attributes, &Enum.at(&1, 1))
    assert ["Photo: Anna Virtanen", "Photo: Anna Virtanen"] = Enum.map(attributes, &Enum.at(&1, 1))

    # The third photo has no credit, so it gets neither.
    assert length(Regex.scan(~r/<figure.*?<\/figure>/s, html)) == 3
  end
end
