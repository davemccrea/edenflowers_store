defmodule EdenflowersWeb.Admin.ExpensesLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest

  alias Edenflowers.Expenses

  setup :verify_on_exit!

  setup :log_in_admin

  test "an expense correction survives bank updates until discarded", %{conn: conn} do
    expense = create_expense("dirty-bank-paid", "Original vendor", "Flowers")
    {:ok, view, _} = live(conn, ~p"/admin/expenses/#{expense.id}")
    view |> form("#expense-form", form: %{vendor_name: "Unsaved vendor"}) |> render_change()

    Expenses.mark_expense_paid_from_bank!(expense, Edenflowers.ShopTime.today(),
      actor: Edenflowers.Actors.system_actor()
    )

    assert has_element?(view, "#expense-form input[name='form[vendor_name]'][value='Unsaved vendor']")
    assert has_element?(view, "#editor-stale-notice")

    view |> element("#editor-stale-notice button") |> render_click()
    {path, _} = assert_redirect(view)
    {:ok, view, _} = live(conn, path)
    assert has_element?(view, "#expense-form input[name='form[vendor_name]'][value='Original vendor']")
    refute has_element?(view, "#editor-stale-notice")
    refute has_element?(view, "button[name=paid_today]")
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

  test "filters to expenses that need review", %{conn: conn} do
    create_expense("unsure", "Unsure Vendor", "Check", sure: false)
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

  test "sorts by the paid date", %{conn: conn} do
    create_expense("paid-early", "Early Vendor", "Done", date: ~D[2026-06-03], paid_on: ~D[2026-06-04])
    create_expense("paid-late", "Late Vendor", "Done", date: ~D[2026-06-01], paid_on: ~D[2026-06-10])

    {:ok, view, _html} = live(conn, ~p"/admin/expenses")
    view |> element("[phx-click=toggle_sort][phx-value-key=paid_on]") |> render_click()
    oldest_first = render(view)
    view |> element("[phx-click=toggle_sort][phx-value-key=paid_on]") |> render_click()
    newest_first = render(view)

    assert position(oldest_first, "Early Vendor") < position(oldest_first, "Late Vendor")
    assert position(newest_first, "Late Vendor") < position(newest_first, "Early Vendor")
  end

  test "a clean expense editor warns when the bank marks it paid and reload catches up", %{conn: conn} do
    expense = create_expense("bank-paid", "Bank Vendor", "Bank payment")
    paid_on = Edenflowers.ShopTime.today()

    {:ok, view, _html} = live(conn, ~p"/admin/expenses/#{expense.id}")
    refute render(view) =~ "Paid #{Edenflowers.Format.date(paid_on, "en")}"

    {:ok, _expense} =
      Expenses.mark_expense_paid_from_bank(expense, paid_on, actor: Edenflowers.Actors.system_actor())

    assert has_element?(view, "#editor-stale-notice[role=alert]")
    view |> element("#editor-stale-notice button") |> render_click()
    {path, _} = assert_redirect(view)
    {:ok, view, _} = live(conn, path)

    assert render(view) =~ "Paid #{Edenflowers.Format.date(paid_on, "en")}"
  end

  test "Finnish visitors get Swedish table controls", %{conn: conn} do
    conn = Plug.Conn.put_session(conn, Localize.Plug.PutLocale.session_key(), "fi")

    {:ok, _view, html} = live(conn, ~p"/admin/expenses")

    assert html =~ ~r/\bFilter\b/
  end

  test "marking paid keeps the corrections", %{conn: conn} do
    expense = create_expense("pay-today", "Typo Vendr", "Flowers", sure: false)

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

  test "offers payment only once flagged figures are confirmed", %{conn: conn} do
    due_on = Date.add(Edenflowers.ShopTime.today(), 14)
    expense = create_expense("confirm-first", "Kukkatukku", "Flowers", sure: false, due_on: due_on)

    {:ok, view, _html} = live(conn, ~p"/admin/expenses/#{expense.id}")
    refute has_element?(view, "button[name=paid_today]")
    refute has_element?(view, "button[name=scheduled_for_due_date]")

    view |> form("#expense-form") |> render_submit()

    assert has_element?(view, "button[name=paid_today]")
    assert has_element?(view, "button[name=scheduled_for_due_date]")
  end

  test "marks a payment scheduled for the due date", %{conn: conn} do
    due_on = Date.add(Edenflowers.ShopTime.today(), 14)
    expense = create_expense("schedule", "Kukkatukku", "Flowers", due_on: due_on)

    {:ok, view, _html} = live(conn, ~p"/admin/expenses/#{expense.id}")
    view |> form("#expense-form") |> render_submit(%{scheduled_for_due_date: "true"})

    assert Ash.get!(Expenses.Expense, expense.id, authorize?: false).paid_on == due_on
    assert render(view) =~ "Scheduled"
    refute has_element?(view, "button[name=scheduled_for_due_date]")
  end

  test "sets and clears the paid date", %{conn: conn} do
    expense = create_expense("paid-on", "Kukkatukku", "Flowers")

    {:ok, view, _html} = live(conn, ~p"/admin/expenses/#{expense.id}")

    view |> form("#expense-form", form: %{paid_on: "2026-06-02"}) |> render_submit()
    assert Ash.get!(Expenses.Expense, expense.id, authorize?: false).paid_on == ~D[2026-06-02]

    view |> form("#expense-form", form: %{paid_on: ""}) |> render_submit()
    assert Ash.get!(Expenses.Expense, expense.id, authorize?: false).paid_on == nil
  end

  test "says when the bank sync went by the amount alone, until Jennie unmarks it", %{conn: conn} do
    expense = create_expense("by-amount", "Kukkatukku", "Flowers")

    {:ok, _expense} =
      Expenses.mark_expense_paid_from_bank(expense, ~D[2026-06-02], %{matched_by_amount: true},
        actor: Edenflowers.Actors.system_actor()
      )

    {:ok, list, _html} = live(conn, ~p"/admin/expenses?needs_review=true")
    assert has_element?(list, "[data-item-id]", "Kukkatukku")

    {:ok, view, _html} = live(conn, ~p"/admin/expenses/#{expense.id}")
    assert has_element?(view, "#expense-review li", "bank payment of the same amount")
    assert render(view) =~ "Needs review"

    view |> element("#expense-actions button", "Mark unpaid") |> render_click()
    refute has_element?(view, "#expense-review")
    refute render(view) =~ "Needs review"
  end

  test "marks a paid expense unpaid", %{conn: conn} do
    expense = create_expense("unpay", "Kukkatukku", "Flowers", paid_on: ~D[2026-06-02])

    {:ok, view, _html} = live(conn, ~p"/admin/expenses/#{expense.id}")
    view |> element("#expense-actions button", "Mark unpaid") |> render_click()

    assert Ash.get!(Expenses.Expense, expense.id, authorize?: false).paid_on == nil
    assert has_element?(view, "button[name=paid_today]")
  end

  describe "bank payments without a receipt" do
    test "links one to the expense Jennie picks, which becomes paid on the booking date", %{conn: conn} do
      booked_on = Date.add(Edenflowers.ShopTime.today(), -10)
      expense = create_expense("hand-link", "Kukkatukku", "Roses", date: booked_on)
      payment = seed_bank_payment("tx-hand", booked_on, "Kukkatukku Oy")

      {:ok, view, _html} = live(conn, ~p"/admin/expenses")
      view |> element("#bank-payment-#{payment.id} button", "Link to expense") |> render_click()
      view |> element("#linkable-expense-#{expense.id} button", "Choose") |> render_click()

      assert Ash.get!(Expenses.Expense, expense.id, authorize?: false).paid_on == booked_on
      refute has_element?(view, "#bank-payment-#{payment.id}")
    end

    test "dismisses one that needs no receipt and restores it", %{conn: conn} do
      payment = seed_bank_payment("tx-fee", Date.add(Edenflowers.ShopTime.today(), -10), "S-Pankki")

      {:ok, view, _html} = live(conn, ~p"/admin/expenses")
      view |> element("#bank-payment-#{payment.id} button", "No receipt needed") |> render_click()
      refute has_element?(view, "#bank-payment-#{payment.id}")

      view |> element("#dismissed-bank-payment-#{payment.id} button", "Restore") |> render_click()
      assert has_element?(view, "#bank-payment-#{payment.id}")
    end

    test "unlinking one on its expense's page puts it back on the list, keeps the paid date and unsaved corrections",
         %{conn: conn} do
      booked_on = Date.add(Edenflowers.ShopTime.today(), -10)
      expense = create_expense("wrong-link", "Kahvila", "Coffee", paid_on: booked_on)
      payment = seed_bank_payment("tx-wrong", booked_on, "Kahvila")
      Expenses.link_expense_bank_payment!(expense, booked_on, "tx-wrong", actor: %{admin: true})

      {:ok, view, _html} = live(conn, ~p"/admin/expenses/#{expense.id}")
      view |> form("#expense-form", form: %{vendor_name: "Kahvila Oy"}) |> render_change()
      view |> element("#expense-bank-payment button", "Unlink") |> render_click()

      assert has_element?(view, ~s(#expense-form input[name="form[vendor_name]"][value="Kahvila Oy"]))

      assert %{bank_transaction_id: nil, paid_on: ^booked_on} =
               Ash.get!(Expenses.Expense, expense.id, authorize?: false)

      {:ok, view, _html} = live(conn, ~p"/admin/expenses")
      assert has_element?(view, "#bank-payment-#{payment.id}")
    end
  end

  defp seed_bank_payment(bank_id, booked_on, counterparty) do
    Ash.Seed.seed!(Edenflowers.Bank.Transaction, %{
      bank_id: bank_id,
      booked_on: booked_on,
      amount: Decimal.new("10.00"),
      currency: "eur",
      counterparty: counterparty
    })
  end

  defp position(html, text), do: html |> :binary.match(text) |> elem(0)

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
          sure: true
        },
        Map.new(attrs)
      ),
      actor: Edenflowers.Actors.system_actor()
    )
  end
end
