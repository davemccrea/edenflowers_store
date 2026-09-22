defmodule EdenflowersWeb.Admin.ExpensesLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  alias AshAuthentication.Jwt
  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.Expenses

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

  test "filters to expenses that have not been reviewed", %{conn: conn} do
    create_expense("unreviewed", "Unreviewed Vendor", "Pending")

    "reviewed"
    |> create_expense("Reviewed Vendor", "Done")
    |> Expenses.mark_expense_reviewed!(authorize?: false)

    {:ok, view, _html} = live(conn, ~p"/admin/expenses?reviewed=false")

    assert has_element?(view, "[data-item-id]", "Unreviewed Vendor")
    refute has_element?(view, "[data-item-id]", "Reviewed Vendor")
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

  defp with_token(user) do
    {:ok, token, _claims} = Jwt.token_for_user(user)
    %{user | __metadata__: Map.put(user.__metadata__ || %{}, :token, token)}
  end
end
