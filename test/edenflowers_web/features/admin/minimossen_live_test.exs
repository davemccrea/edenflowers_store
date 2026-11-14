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
    assert has_element?(view, "#minimossen dt", "Sales in week 44")
  end
end
