defmodule EdenflowersWeb.Marketing.FaqLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "the Courses section explains cancelling and the late-cancellation fee", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/faq")

    assert has_element?(view, "#courses h2", "Courses")
    assert has_element?(view, "#courses dd", "Reply to your confirmation email")
    assert has_element?(view, "#courses dd", "at least 7 days before the course")
    assert has_element?(view, "#courses dd", "late-cancellation fee")
  end

  test "the delivery answer gives the same-day deadline from the shop calendar", %{conn: conn} do
    Generator.shop_calendar(same_day: true, order_deadline: ~T[11:30:00])

    {:ok, view, _html} = live(conn, ~p"/en/faq")

    assert has_element?(view, "dd", "Order by 11:30")
  end

  test "the delivery answer leaves out same day when the shop has it off", %{conn: conn} do
    Generator.shop_calendar(same_day: false)

    {:ok, view, _html} = live(conn, ~p"/en/faq")

    assert has_element?(view, "dd", "The earliest is the next day the shop is open.")
    refute has_element?(view, "dd", "same day")
  end
end
