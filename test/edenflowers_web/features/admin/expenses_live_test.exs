defmodule EdenflowersWeb.Admin.ExpensesLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import ExUnit.CaptureLog
  import Generator
  import Mox
  import Phoenix.LiveViewTest

  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.Expenses

  setup :verify_on_exit!

  setup %{conn: conn} do
    admin = generate(admin_user()) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(admin)

    %{conn: conn}
  end

  test "searches expenses by vendor", %{conn: conn} do
    create_expense("vendor-match", "Northern Blooms", "Weekly flowers")
    create_expense("vendor-miss", "Office Depot", "Printer paper")

    {:ok, view, _html} = live(conn, ~p"/admin/expenses?search=northern")

    assert has_element?(view, "[data-item-id]", "Northern Blooms")
    refute has_element?(view, "[data-item-id]", "Office Depot")
  end

  test "searches expenses by description", %{conn: conn} do
    create_expense("description-match", "Acme Oy", "Office chairs")
    create_expense("description-miss", "Contoso Oy", "Printer paper")

    {:ok, view, _html} = live(conn, ~p"/admin/expenses?search=chairs")

    assert has_element?(view, "[data-item-id]", "Acme Oy")
    refute has_element?(view, "[data-item-id]", "Contoso Oy")
  end

  test "lists the newest expenses first", %{conn: conn} do
    create_expense("older", "Older Vendor", "Older", date: ~D[2026-01-05])
    create_expense("newer", "Newer Vendor", "Newer", date: ~D[2026-03-10])

    {:ok, _view, html} = live(conn, ~p"/admin/expenses")

    {newer_position, _} = :binary.match(html, "Newer Vendor")
    {older_position, _} = :binary.match(html, "Older Vendor")
    assert newer_position < older_position
  end

  test "lists unreviewed expenses above reviewed ones", %{conn: conn} do
    create_expense("older-unreviewed", "Unreviewed Vendor", "Pending", date: ~D[2026-01-05])

    "newer-reviewed"
    |> create_expense("Reviewed Vendor", "Done", date: ~D[2026-03-10])
    |> Expenses.mark_expense_reviewed!(authorize?: false)

    {:ok, _view, html} = live(conn, ~p"/admin/expenses")

    {unreviewed_position, _} = :binary.match(html, "Unreviewed Vendor")
    {reviewed_position, _} = :binary.match(html, "Reviewed Vendor")
    assert unreviewed_position < reviewed_position
  end

  test "filters to expenses that have not been reviewed", %{conn: conn} do
    create_expense("unreviewed", "Unreviewed Vendor", "Pending")

    "reviewed"
    |> create_expense("Reviewed Vendor", "Done")
    |> Expenses.mark_expense_reviewed!(authorize?: false)

    {:ok, view, _html} = live(conn, ~p"/admin/expenses?reviewed=false")

    assert has_element?(view, "[data-item-id]", "Unreviewed Vendor")
    refute has_element?(view, "[data-item-id]", "Reviewed Vendor")
  end

  test "translates the table controls", %{conn: conn} do
    conn = Plug.Conn.put_session(conn, Localize.Plug.PutLocale.session_key(), "fi")

    {:ok, _view, html} = live(conn, ~p"/admin/expenses")

    assert html =~ "Suodattimet"
  end

  test "saving and marking reviewed keeps the corrections", %{conn: conn} do
    expense = create_expense("save-review", "Typo Vendr", "Flowers")

    {:ok, view, _html} = live(conn, ~p"/admin/expenses/#{expense.id}")

    view
    |> form("#expense-form", form: %{vendor_name: "Typo Vendor"})
    |> render_submit(%{review: "true"})

    assert_push_event(view, "admin-form-saved", %{id: "expense-form"})

    reviewed = Ash.get!(Expenses.Expense, expense.id, authorize?: false)
    assert reviewed.vendor_name == "Typo Vendor"
    assert reviewed.reviewed_at
  end

  test "saving corrections alone leaves the expense unreviewed", %{conn: conn} do
    expense = create_expense("save-only", "Typo Vendr", "Flowers")

    {:ok, view, _html} = live(conn, ~p"/admin/expenses/#{expense.id}")

    view
    |> form("#expense-form", form: %{vendor_name: "Typo Vendor"})
    |> render_submit()

    assert_push_event(view, "admin-form-saved", %{id: "expense-form"})

    saved = Ash.get!(Expenses.Expense, expense.id, authorize?: false)
    assert saved.vendor_name == "Typo Vendor"
    refute saved.reviewed_at
  end

  test "sets and clears the paid date", %{conn: conn} do
    expense = create_expense("paid-on", "Kukkatukku", "Flowers")

    {:ok, view, _html} = live(conn, ~p"/admin/expenses/#{expense.id}")

    view |> form("#expense-form", form: %{paid_on: "2026-06-02"}) |> render_submit()
    assert Ash.get!(Expenses.Expense, expense.id, authorize?: false).paid_on == ~D[2026-06-02]

    view |> form("#expense-form", form: %{paid_on: ""}) |> render_submit()
    assert Ash.get!(Expenses.Expense, expense.id, authorize?: false).paid_on == nil
  end

  test "deletes an expense along with its import", %{conn: conn} do
    expense = create_expense("delete-me", "Mistake Oy", "Not an expense")

    Expenses.ExpenseImport
    |> Ash.Changeset.for_create(:record, %{document_id: "delete-me", organization_id: "org"})
    |> Ash.Changeset.force_change_attribute(:expense_id, expense.id)
    |> Ash.create!(authorize?: false)

    expect(Edenflowers.External.PapraAPI.Mock, :remove_document_tag, fn "delete-me", "receipt" -> :ok end)
    expect(Edenflowers.External.PapraAPI.Mock, :remove_document_tag, fn "delete-me", "processed" -> :ok end)

    {:ok, view, _html} = live(conn, ~p"/admin/expenses/#{expense.id}")

    assert {:error, {:live_redirect, %{to: "/admin/expenses"}}} =
             view |> element("#expense-actions button[phx-click=delete]", "Delete") |> render_click()

    assert Ash.read!(Expenses.Expense, authorize?: false) == []
    assert Ash.read!(Expenses.ExpenseImport, authorize?: false) == []
  end

  test "keeps the expense when the Papra tags can't be removed", %{conn: conn} do
    expense = create_expense("papra-down", "Acme Oy", "Flowers")

    expect(Edenflowers.External.PapraAPI.Mock, :remove_document_tag, fn _, _ ->
      {:error, {:papra_http_error, 503}}
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/expenses/#{expense.id}")

    html =
      ExUnit.CaptureLog.with_log(fn ->
        view |> element("#expense-actions button[phx-click=delete]", "Delete") |> render_click()
      end)
      |> elem(0)

    assert html =~ "Papra couldn&#39;t be reached"
    assert Ash.get!(Expenses.Expense, expense.id, authorize?: false)
  end

  describe "monthly report download" do
    test "the Export drawer defaults the month to the previous one", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/expenses")

      previous_month =
        Edenflowers.ShopTime.today() |> Date.beginning_of_month() |> Date.add(-1) |> Date.to_iso8601()

      assert has_element?(view, ~s(button[phx-click*="phx-show"][phx-click*="export-drawer"]), "Export")

      assert has_element?(
               view,
               ~s(#report-form input[name="month"][value="#{String.slice(previous_month, 0, 7)}"])
             )
    end

    test "shows the report building, then pushes the month's zip", %{conn: conn} do
      create_expense("report-doc", "Kukkatukku", "Flowers", date: ~D[2026-09-03])

      expect(Edenflowers.External.PapraAPI.Mock, :fetch_document, fn _, _ ->
        {:ok, %{body: "%PDF", content_type: "application/pdf"}}
      end)

      expect(Edenflowers.External.StripeAPI.Mock, :list_balance_transactions_page, fn _, nil ->
        {:ok, %{data: [], has_more: false}}
      end)

      {:ok, view, _html} = live(conn, ~p"/admin/expenses")

      assert view |> form("#report-form", month: "2026-09") |> render_submit() =~ "Building report…"
      assert has_element?(view, "#report-form button[disabled]")

      render_async(view)

      assert_push_event(view, "download", %{filename: "redovisning-2026-09.zip", content: content})
      assert {:ok, files} = :zip.unzip(Base.decode64!(content), [:memory])
      assert {~c"kvitton/001_2026-09-03_Kukkatukku.pdf", "%PDF"} in files
      refute has_element?(view, "#report-form button[disabled]")
    end

    test "flashes an error and pushes nothing when Stripe can't be reached", %{conn: conn} do
      expect(Edenflowers.External.StripeAPI.Mock, :list_balance_transactions_page, fn _, _ -> {:error, :timeout} end)

      {:ok, view, _html} = live(conn, ~p"/admin/expenses")

      {html, log} =
        with_log(fn ->
          view |> form("#report-form", month: "2026-09") |> render_submit()
          render_async(view)
        end)

      assert log =~ ~s(Monthly report for "2026-09" failed:)
      assert html =~ "couldn&#39;t be built"
      refute_push_event(view, "download", %{})
      refute has_element?(view, "#report-form button[disabled]")
    end

    test "pushes the zip and flashes when a receipt can't be fetched", %{conn: conn} do
      create_expense("report-missing", "Kukkatukku", "Flowers", date: ~D[2026-09-03])
      expect(Edenflowers.External.PapraAPI.Mock, :fetch_document, fn _, _ -> {:error, :timeout} end)

      expect(Edenflowers.External.StripeAPI.Mock, :list_balance_transactions_page, fn _, nil ->
        {:ok, %{data: [], has_more: false}}
      end)

      {:ok, view, _html} = live(conn, ~p"/admin/expenses")

      {html, log} =
        with_log(fn ->
          view |> form("#report-form", month: "2026-09") |> render_submit()
          render_async(view)
        end)

      assert log =~ "Receipt report-missing couldn't be fetched"
      assert_push_event(view, "download", %{filename: "redovisning-2026-09.zip"})
      assert html =~ "Receipts missing from the report: 1."
    end

    test "flashes an error for a malformed month", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/expenses")

      assert view |> render_submit("download_report", %{"month" => "2026-13"}) =~ "couldn&#39;t be built"
    end
  end

  defp create_expense(document_id, vendor_name, description, attrs \\ []) do
    Expenses.ingest_expense!(
      Map.merge(
        %{
          document_id: document_id,
          vendor_name: vendor_name,
          description: description,
          date: ~D[2026-06-01],
          total_amount: "10.00",
          currency: :eur,
          confidence: :high
        },
        Map.new(attrs)
      ),
      actor: Edenflowers.Actors.system_actor()
    )
  end
end
