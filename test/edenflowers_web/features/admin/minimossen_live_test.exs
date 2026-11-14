defmodule EdenflowersWeb.Admin.MinimossenLiveTest do
  use EdenflowersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Generator

  setup %{conn: conn}, do: %{conn: log_in(conn, generate(admin_user()) |> with_token())}

  test "says so before any report is imported", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/minimossen")
    assert has_element?(view, "#minimossen", "No Winpos reports imported yet.")
  end

  defp record(week_start, code, gross) do
    Edenflowers.Minimossen.record_minimossen_sales!(
      %{week_start: week_start, group_code: code, group_name: "Group #{code}", gross: gross},
      actor: Edenflowers.Actors.system_actor()
    )
  end

  test "shows the latest week, with each week in the table", %{conn: conn} do
    # 52 weeks before week 45, but none before week 44.
    record(~D[2025-11-03], "3", "40.00")
    record(~D[2026-10-26], "3", "50.00")
    record(~D[2026-11-02], "3", "50.00")

    {:ok, view, _html} = live(conn, ~p"/admin/minimossen")
    assert has_element?(view, "#minimossen dt", "Week 45")
    assert has_element?(view, "#minimossen-table tr", "Week 45 50,00 € 50,00 € +25%")
    assert has_element?(view, "#minimossen-table tr", "Week 44 50,00 € 50,00 € –")
  end

  test "keeps the period and group in the URL", %{conn: conn} do
    record(~D[2026-11-02], "3", "50.00")
    record(~D[2026-11-02], "6", "7.00")

    {:ok, view, _html} = live(conn, ~p"/admin/minimossen?period=month&group=3")
    assert has_element?(view, "a[aria-current=page]", "Month")
    assert has_element?(view, "#minimossen-groups a[aria-current=page]", "Flowers")
    assert has_element?(view, "#minimossen dt", "Flowers · November 2026")
    assert has_element?(view, "#minimossen-total", Edenflowers.Format.currency(Decimal.new("50.00"), "en"))
    # The month is still under way.
    assert has_element?(view, "#minimossen-table th", "Nov 2026 partial")

    view |> element("a", "Week") |> render_click()
    assert_patch(view, ~p"/admin/minimossen?group=3")

    view |> element("#minimossen-groups a", "All groups") |> render_click()
    assert_patch(view, ~p"/admin/minimossen")
  end

  test "shows a past week in the headline until sent back to the latest", %{conn: conn} do
    record(~D[2026-10-26], "3", "20.00")
    record(~D[2026-11-02], "3", "50.00")

    {:ok, view, _html} = live(conn, ~p"/admin/minimossen")
    view |> element("#minimossen-table th a", "Week 44") |> render_click()
    assert_patch(view, ~p"/admin/minimossen?at=2026-10-26")
    assert has_element?(view, "#minimossen dt", "Week 44")
    assert has_element?(view, "#minimossen-total", Edenflowers.Format.currency(Decimal.new("20"), "en"))
    assert has_element?(view, "#minimossen-table tr[aria-current]", "Week 44")

    view |> element("#minimossen-latest", "Back to Week 45") |> render_click()
    assert_patch(view, ~p"/admin/minimossen")
    assert has_element?(view, "#minimossen-total", Edenflowers.Format.currency(Decimal.new("50"), "en"))
  end
end
