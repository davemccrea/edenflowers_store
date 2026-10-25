defmodule EdenflowersWeb.Marketing.TermsLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  test "reads the delivery distance and cancellation deadline live", %{conn: conn} do
    generate(fulfillment_option(fulfillment_method: :delivery, rate_type: :dynamic, max_dist_km: 17))
    days = Edenflowers.Orders.Subscription.change_deadline_days()

    {:ok, view, _html} = live(conn, ~p"/en/terms")

    assert has_element?(view, "#delivery", "I deliver within 17 km of the shop")
    assert has_element?(view, "#cancellation", "until #{days} days before delivery or pickup")
    assert has_element?(view, "#seller", EdenflowersWeb.Business.business_id())
  end

  test "leaves out the distance when nothing is delivered by distance", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/terms")

    assert has_element?(view, "#delivery", "I deliver on the day you choose at checkout.")
  end
end
