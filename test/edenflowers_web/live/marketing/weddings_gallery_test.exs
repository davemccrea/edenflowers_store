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

    assert length(links) == 15

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

  # The lightbox clones each figure's figcaption, so every photo needs one.
  test "photographer credits are available to the lightbox", %{html: html} do
    captions =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("#wedding-gallery figure figcaption")
      |> Enum.map(&(&1 |> LazyHTML.text() |> String.split() |> Enum.join(" ")))

    assert length(captions) == 15
    assert ["Photo: Anna Riska" | _] = captions
  end

  test "thumbnails support the widest column at 2x without loading lightbox sizes", %{html: html} do
    images = html |> LazyHTML.from_fragment() |> LazyHTML.query("#wedding-gallery img")

    assert Enum.count(images) == 15

    for image <- images do
      assert LazyHTML.attribute(image, "width") == ["480"]
      assert [srcset] = LazyHTML.attribute(image, "srcset")

      widths =
        Regex.scan(~r/ (\d+)w/, srcset)
        |> Enum.map(fn [_, width] -> String.to_integer(width) end)

      assert Enum.min(widths) == 320
      assert Enum.max(widths) == 960
      assert [sizes] = LazyHTML.attribute(image, "sizes")
      assert sizes =~ "(min-width: 96rem) calc(90.5rem / 4)"
      assert sizes =~ "(min-width: 80rem) calc(74.5rem / 4)"
      assert String.ends_with?(sizes, "calc((100vw - 2.5rem) / 2)")
    end
  end

  test "gallery images load lazily", %{html: html} do
    images =
      html |> LazyHTML.from_fragment() |> LazyHTML.query("#wedding-gallery img") |> Enum.to_list()

    for image <- images do
      assert LazyHTML.attribute(image, "loading") == ["lazy"]
      assert LazyHTML.attribute(image, "fetchpriority") == []
    end
  end
end
