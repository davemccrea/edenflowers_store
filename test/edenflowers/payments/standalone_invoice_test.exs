defmodule Edenflowers.Payments.StandaloneInvoiceTest do
  use Edenflowers.DataCase, async: false
  import Generator
  alias Edenflowers.Payments
  alias Edenflowers.Payments.Invoice

  setup do
    %{admin: generate(admin_user())}
  end

  defp attrs do
    %{
      buyer_name: "Alice Buyer",
      buyer_email: "alice@example.com",
      buyer_address: "Street 1, Vaasa",
      locale: "fi",
      lines: [
        %{description: "Wedding flowers", quantity: "1.5", unit_price: "10.01", vat_rate: "25.5"},
        %{description: "Books", quantity: "2", unit_price: "5", vat_rate: "14"}
      ]
    }
  end

  test "drafts are unnumbered, editable, and absent from receivables", %{admin: admin} do
    assert {:ok, draft} = Payments.create_invoice(%{}, actor: admin)
    assert draft.number == nil
    assert draft.content == nil
    assert Ash.load!(draft, :status).status == :draft
    assert {:ok, draft} = Payments.update_invoice_draft(draft, attrs(), actor: admin)
    assert {:ok, []} = Payments.list_open_invoices(Date.add(Date.utc_today(), 40), actor: admin)
    assert {:ok, issued} = Payments.issue_invoice(draft, actor: admin)
    assert issued.number == Invoice.first_number()
    assert Decimal.equal?(issued.amount, "25.02")
    assert issued.financial_snapshot["base"] == "20.74"
    assert issued.financial_snapshot["vat"] == "4.28"
    assert Enum.count(issued.financial_snapshot["vat_breakdown"]) == 2
    assert {:error, _} = Payments.update_invoice_draft(issued, %{buyer_name: "Changed"}, actor: admin)
    assert {:error, _} = Payments.issue_invoice(draft, actor: admin)
    assert Ash.get!(Invoice, draft.id, authorize?: false).content == issued.content
  end

  test "failed issuance consumes no number and rejects invalid or empty financials", %{admin: admin} do
    for lines <- [
          [],
          [%{description: "Invalid", quantity: "0", unit_price: "10", vat_rate: "25.5"}],
          [%{description: "Invalid", quantity: "1", unit_price: "10", vat_rate: "101"}]
        ] do
      assert {:ok, draft} = Payments.create_invoice(Map.put(attrs(), :lines, lines), actor: admin)
      assert {:error, _} = Payments.issue_invoice(draft, actor: admin)
      assert Ash.get!(Invoice, draft.id, authorize?: false).number == nil
    end

    assert {:ok, draft} = Payments.create_invoice(attrs(), actor: admin)
    assert {:ok, issued} = Payments.issue_invoice(draft, actor: admin)
    assert issued.number == Invoice.first_number()
  end

  test "stale draft edits cannot alter an issued invoice; documents freeze seller and buyer", %{admin: admin} do
    {:ok, draft} = Payments.create_invoice(attrs(), actor: admin)
    {:ok, issued} = Payments.issue_invoice(draft, actor: admin)
    assert {:error, _} = Payments.update_invoice_draft(draft, %{lines: []}, actor: admin)
    original = Application.fetch_env!(:edenflowers, :seller)
    Application.put_env(:edenflowers, :seller, Map.put(Map.new(original), :name, "Changed seller"))
    on_exit(fn -> Application.put_env(:edenflowers, :seller, original) end)
    current = Ash.get!(Invoice, issued.id, authorize?: false)
    assert current.seller_snapshot == issued.seller_snapshot
    assert current.content == issued.content
    assert current.financial_snapshot == issued.financial_snapshot
  end

  test "only admins draft and issue", %{admin: admin} do
    assert {:error, _} = Payments.create_invoice(attrs(), actor: nil)
    {:ok, draft} = Payments.create_invoice(attrs(), actor: admin)
    assert {:error, _} = Payments.issue_invoice(draft, actor: nil)
  end
end
