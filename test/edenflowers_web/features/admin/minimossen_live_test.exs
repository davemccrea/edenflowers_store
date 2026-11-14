defmodule EdenflowersWeb.Admin.MinimossenLiveTest do
  use EdenflowersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Generator

  setup %{conn: conn}, do: %{conn: log_in(conn, generate(admin_user()) |> with_token())}

  test "says so before any report is imported", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/minimossen")
    assert has_element?(view, "#minimossen-card", "No Winpos reports imported yet.")
  end

  test "shows the latest week and the week of a clicked bar", %{conn: conn} do
    for week_start <- [~D[2026-10-26], ~D[2026-11-02]] do
      Edenflowers.Minimossen.record_minimossen_sales!(
        %{week_start: week_start, group_code: "3", group_name: "Flowers", gross: "50.00"},
        actor: Edenflowers.Actors.system_actor()
      )
    end

    {:ok, view, _html} = live(conn, ~p"/admin/minimossen")
    assert has_element?(view, "#minimossen dt", "Sales in week 45")

    view |> element("#minimossen-bars button[phx-value-start='2026-10-26']") |> render_click()
    assert_patch(view, ~p"/admin/minimossen?at=2026-10-26")
    assert has_element?(view, "#minimossen dt", "Sales in week 44")
  end

  test "keeps the period and group in the URL", %{conn: conn} do
    Edenflowers.Minimossen.record_minimossen_sales!(
      %{week_start: ~D[2026-11-02], group_code: "3", group_name: "Flowers", gross: "50.00"},
      actor: Edenflowers.Actors.system_actor()
    )

    {:ok, view, _html} = live(conn, ~p"/admin/minimossen?period=month&group=3")
    assert has_element?(view, "a[aria-current=page]", "Month")
    assert has_element?(view, "#minimossen-groups button[aria-pressed=true]", "Flowers")
    # The month is still under way.
    assert has_element?(view, "#minimossen-table th", "Nov 2026 partial")

    view |> element("a", "Year") |> render_click()
    assert_patch(view, ~p"/admin/minimossen?group=3&period=year")
  end
end
