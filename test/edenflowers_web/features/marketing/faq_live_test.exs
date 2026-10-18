defmodule EdenflowersWeb.Marketing.FaqLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "the Courses section explains cancelling and the late-cancellation fee", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/faq")

    assert has_element?(view, "#courses h2", "Courses")
    assert has_element?(view, "#courses dd", "Reply to your confirmation email")
    assert has_element?(view, "#courses dd", "at least 7 days before the course")
    assert has_element?(view, "#courses dd", "late-cancellation fee")
  end
end
