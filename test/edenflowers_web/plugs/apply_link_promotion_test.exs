defmodule EdenflowersWeb.Plugs.ApplyLinkPromotionTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator

  alias Edenflowers.Orders

  test "a storefront link's code goes on the browser's cart", %{conn: conn} do
    generate(promotion(code: "AB12CD"))

    conn = get(conn, "/en", code: "ab12cd", utm_source: "card")

    assert Phoenix.Flash.get(conn.assigns.flash, :success) =~ "AB12CD"
    assert Orders.get_storefront_cart!(get_session(conn, :visitor_id), actor: nil).promotion_code == "AB12CD"
  end

  test "an unknown code still shows the page, with no notice", %{conn: conn} do
    conn = get(conn, "/en", code: "NOPE")

    assert html_response(conn, 200)
    assert Phoenix.Flash.get(conn.assigns.flash, :success) == nil
  end
end
