defmodule EdenflowersWeb.Store.StoreLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "offers contact when the catalogue has no categories", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/store/bouquets")

    assert has_element?(view, "h1", "Store")
    assert has_element?(view, "#store-products h2", "I'm preparing the next collection")
    assert has_element?(view, "#store-products a[href='/contact']", "Get in touch")
    refute has_element?(view, "nav[aria-label='Categories']")
  end
end
