defmodule EdenflowersWeb.Marketing.CondolencesGalleryTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "each gallery link requests the exact size it tells PhotoSwipe to expect", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/condolences")

    links =
      Regex.scan(
        ~r/<a[^>]*href="([^"]+)"[^>]*data-pswp-width="(\d+)"[^>]*data-pswp-height="(\d+)"/,
        html
      )

    assert length(links) == 30

    for [_, href, declared_width, declared_height] <- links do
      assert [_, ^declared_width, ^declared_height] = Regex.run(~r/rs:fill:(\d+):(\d+)/, href)
    end
  end
end
