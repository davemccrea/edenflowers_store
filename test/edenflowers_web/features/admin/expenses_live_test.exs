defmodule EdenflowersWeb.Admin.ExpensesLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest

  alias Edenflowers.Expenses

  setup :verify_on_exit!

  setup :log_in_admin

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

  test "lists unpaid expenses first, then ones needing review", %{conn: conn} do
    create_expense("paid", "Paid Vendor", "Done", date: ~D[2026-03-10], paid_on: ~D[2026-03-10])
    create_expense("unsure", "Unsure Vendor", "Check", date: ~D[2026-01-05], paid_on: ~D[2026-01-05], confidence: :low)
    create_expense("unpaid", "Unpaid Vendor", "Pending", date: ~D[2026-01-01])

    {:ok, _view, html} = live(conn, ~p"/admin/expenses")

    positions = Enum.map(["Unpaid Vendor", "Unsure Vendor", "Paid Vendor"], &elem(:binary.match(html, &1), 0))
    assert positions == Enum.sort(positions)
  end

  test "filters to expenses that need review", %{conn: conn} do
    create_expense("unsure", "Unsure Vendor", "Check", confidence: :medium)
    create_expense("sure", "Sure Vendor", "Fine")

    {:ok, view, _html} = live(conn, ~p"/admin/expenses?needs_review=true")

    assert has_element?(view, "[data-item-id]", "Unsure Vendor")
    refute has_element?(view, "[data-item-id]", "Sure Vendor")
  end

  test "filters to unpaid expenses", %{conn: conn} do
    create_expense("unpaid", "Unpaid Vendor", "Pending")
    create_expense("paid", "Paid Vendor", "Done", paid_on: ~D[2026-06-01])

    {:ok, view, _html} = live(conn, ~p"/admin/expenses?paid=false")

    assert has_element?(view, "[data-item-id]", "Unpaid Vendor")
    refute has_element?(view, "[data-item-id]", "Paid Vendor")
  end

  test "translates the table controls", %{conn: conn} do
    conn = Plug.Conn.put_session(conn, Localize.Plug.PutLocale.session_key(), "fi")

    {:ok, _view, html} = live(conn, ~p"/admin/expenses")

    assert html =~ "Suodattimet"
  end

  test "marking paid today keeps the corrections", %{conn: conn} do
    expense = create_expense("pay-today", "Typo Vendr", "Flowers", confidence: :low)

    {:ok, view, _html} = live(conn, ~p"/admin/expenses/#{expense.id}")

    view
    |> form("#expense-form", form: %{vendor_name: "Typo Vendor"})
    |> render_submit(%{paid_today: "true"})

    assert_push_event(view, "admin-form-saved", %{id: "expense-form"})

    saved = Ash.get!(Expenses.Expense, expense.id, authorize?: false, load: :needs_review)
    assert saved.vendor_name == "Typo Vendor"
    assert saved.paid_on == Edenflowers.ShopTime.today()
    refute saved.needs_review
    refute has_element?(view, "button[name=paid_today]")
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

    {:ok, view, _html} = live(conn, ~p"/admin/expenses/#{expense.id}")

    assert {:error, {:live_redirect, %{to: "/admin/expenses"}}} =
             view |> element("#expense-actions button[phx-click=delete]", "Delete") |> render_click()

    assert Ash.read!(Expenses.Expense, authorize?: false) == []
    assert Ash.read!(Expenses.ExpenseImport, authorize?: false) == []
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
