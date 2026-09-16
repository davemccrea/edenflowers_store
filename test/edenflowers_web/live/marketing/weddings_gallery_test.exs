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

    assert length(links) == 17

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
    assert ["Photo: Anna Riska" | _] = Enum.map(attributes, &Enum.at(&1, 1))
    assert length(attributes) == 17
    assert length(Regex.scan(~r/<figure.*?<\/figure>/s, html)) == 17
  end

  test "thumbnails support the widest column at 2x without loading lightbox sizes", %{html: html} do
    images = html |> LazyHTML.from_fragment() |> LazyHTML.query("#wedding-gallery img")

    assert Enum.count(images) == 17

    for image <- images do
      assert LazyHTML.attribute(image, "width") == ["480"]
      assert [srcset] = LazyHTML.attribute(image, "srcset")

      widths =
        Regex.scan(~r/ (\d+)w/, srcset)
        |> Enum.map(fn [_, width] -> String.to_integer(width) end)

      assert Enum.min(widths) == 320
      assert Enum.max(widths) == 960
      assert [sizes] = LazyHTML.attribute(image, "sizes")
      assert sizes =~ "(min-width: 96rem) 30rem"
      assert String.ends_with?(sizes, "calc((100vw - 3rem) / 2)")
    end
  end

  test "only the first gallery image is prioritised", %{html: html} do
    [first | remaining] =
      html |> LazyHTML.from_fragment() |> LazyHTML.query("#wedding-gallery img") |> Enum.to_list()

    assert LazyHTML.attribute(first, "loading") == ["eager"]
    assert LazyHTML.attribute(first, "fetchpriority") == ["high"]

    for image <- remaining do
      assert LazyHTML.attribute(image, "loading") == ["lazy"]
      assert LazyHTML.attribute(image, "fetchpriority") == []
    end
  end
end
