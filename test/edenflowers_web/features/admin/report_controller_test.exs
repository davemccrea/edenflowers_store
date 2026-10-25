defmodule EdenflowersWeb.Admin.ReportControllerTest do
  use EdenflowersWeb.ConnCase, async: true

  import ExUnit.CaptureLog
  import Mox
  import Phoenix.LiveViewTest

  alias Edenflowers.Expenses

  setup :verify_on_exit!

  setup :log_in_admin

  test "the Overview report form defaults to the previous month", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin")

    previous_month =
      Edenflowers.ShopTime.today() |> Date.beginning_of_month() |> Date.add(-1) |> Date.to_iso8601()

    assert has_element?(
             view,
             ~s(#report-form[action="/admin/reports"] input[name="month"][value="#{String.slice(previous_month, 0, 7)}"])
           )
  end

  test "downloads the month's zip", %{conn: conn} do
    Expenses.ingest_expense!(
      %{
        document_id: "report-doc",
        vendor_name: "Kukkatukku",
        description: "Flowers",
        date: ~D[2026-09-03],
        total_amount: "10.00",
        currency: :eur,
        confidence: :high
      },
      actor: Edenflowers.Actors.system_actor()
    )

    expect(Edenflowers.External.PapraAPI.Mock, :fetch_document, fn _, _ ->
      {:ok, %{body: "%PDF", content_type: "application/pdf"}}
    end)

    expect(Edenflowers.External.StripeAPI.Mock, :list_balance_transactions_page, fn _, nil ->
      {:ok, %{data: [], has_more: false}}
    end)

    conn = get(conn, ~p"/admin/reports?month=2026-09")

    assert get_resp_header(conn, "content-disposition") == [~s(attachment; filename="redovisning-2026-09.zip")]
    assert {:ok, files} = :zip.unzip(conn.resp_body, [:memory])
    assert {~c"kvitton/001_2026-09-03_Kukkatukku.pdf", "%PDF"} in files
  end

  test "flashes an error on Overview when Stripe can't be reached", %{conn: conn} do
    expect(Edenflowers.External.StripeAPI.Mock, :list_balance_transactions_page, fn _, _ -> {:error, :timeout} end)

    {conn, log} = with_log(fn -> get(conn, ~p"/admin/reports?month=2026-09") end)

    assert redirected_to(conn) == ~p"/admin"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "couldn't be built"
    assert log =~ ~s(Monthly report for "2026-09" failed:)
  end

  test "flashes an error for a malformed month", %{conn: conn} do
    {conn, _log} = with_log(fn -> get(conn, ~p"/admin/reports?month=2026-13") end)

    assert redirected_to(conn) == ~p"/admin"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "couldn't be built"
  end

  test "is not found for anyone but an admin" do
    conn = get(build_conn(), ~p"/admin/reports?month=2026-09")

    assert conn.status == 404
  end
end
