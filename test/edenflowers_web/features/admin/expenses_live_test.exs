defmodule EdenflowersWeb.Admin.ExpensesLiveTest do
  use EdenflowersWeb.ConnCase, async: true

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

  defp create_expense(document_id, vendor_name, description, attrs \\ []) do
    Expenses.ingest_expense!(
      Map.merge(
        %{
          document_id: document_id,
          vendor_name: vendor_name,
          description: description,
          confidence: :high
        },
        Map.new(attrs)
      ),
      actor: Edenflowers.Actors.system_actor()
    )
  end
end
