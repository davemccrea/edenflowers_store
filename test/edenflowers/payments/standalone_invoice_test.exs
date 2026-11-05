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
      supply_date: ~D[2026-11-02],
      locale: "fi",
      lines: [
        %{description: "Wedding flowers", quantity: "1.5", unit_price: "10.01", vat_rate: "25.5"},
        %{description: "Books", quantity: "2", unit_price: "5", vat_rate: "14"}
      ]
    }
  end

  test "a draft may hold an unfinished line but not a wrong one, and issuing needs it finished", %{admin: admin} do
    line = %{description: "Flowers", quantity: "1", unit_price: "20", vat_rate: "25.5"}

    for {field, value} <- [quantity: "0", quantity: "NaN", unit_price: "-0.01", vat_rate: "100.1", vat_rate: "-1"] do
      assert {:error, _} = Payments.create_invoice(%{attrs() | lines: [Map.put(line, field, value)]}, actor: admin)
    end

    {:ok, draft} = Payments.create_invoice(%{attrs() | lines: [%{line | unit_price: nil}]}, actor: admin)
    assert {:error, _} = Payments.issue_invoice(draft, actor: admin)
    {:ok, draft} = Payments.update_invoice_draft(draft, %{lines: [%{line | unit_price: "20,50"}]}, actor: admin)
    assert {:ok, issued} = Payments.issue_invoice(draft, actor: admin)
    assert Decimal.equal?(issued.amount, "20.50")
  end

  test "a business customer's Y-tunnus needs its check digit", %{admin: admin} do
    business = Map.merge(attrs(), %{business_customer: true, company_name: "Kukka Oy", billing_address: "Street 1"})
    assert {:error, _} = Payments.create_invoice(Map.put(business, :business_id, "2944459-5"), actor: admin)
    assert {:ok, draft} = Payments.create_invoice(Map.put(business, :business_id, " 2944459-6 "), actor: admin)
    assert draft.business_id == "2944459-6"
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

  test "only a draft can be deleted", %{admin: admin} do
    {:ok, draft} = Payments.create_invoice(attrs(), actor: admin)
    assert :ok = Payments.destroy_invoice_draft(draft, actor: admin)
    assert Ash.get(Invoice, draft.id, authorize?: false) |> elem(0) == :error

    {:ok, draft} = Payments.create_invoice(attrs(), actor: admin)
    {:ok, issued} = Payments.issue_invoice(draft, actor: admin)
    assert {:error, _} = Payments.destroy_invoice_draft(draft, actor: admin)
    assert Ash.get!(Invoice, issued.id, authorize?: false).number == issued.number
  end

  test "failed issuance consumes no number and rejects unfinished, zero or empty financials", %{admin: admin} do
    for lines <- [
          [],
          [%{description: "Unfinished", quantity: "1", unit_price: "10", vat_rate: nil}],
          [%{description: "Free sample", quantity: "1", unit_price: "0", vat_rate: "25.5"}]
        ] do
      assert {:ok, draft} = Payments.create_invoice(Map.put(attrs(), :lines, lines), actor: admin)
      assert {:error, _} = Payments.issue_invoice(draft, actor: admin)
      assert Ash.get!(Invoice, draft.id, authorize?: false).number == nil
    end

    assert {:ok, draft} = Payments.create_invoice(attrs(), actor: admin)
    assert {:ok, issued} = Payments.issue_invoice(draft, actor: admin)
    assert issued.number == Invoice.first_number()
  end

  test "an invoice is dated the day it is issued and due its whole payment term later", %{admin: admin} do
    {:ok, draft} = Payments.create_invoice(Map.put(attrs(), :payment_term_days, 30), actor: admin)
    assert draft.invoice_date == nil
    {:ok, issued} = Payments.issue_invoice(draft, actor: admin)
    today = Edenflowers.ShopTime.today()
    assert issued.invoice_date == today
    assert issued.due_date == Date.add(today, 30)
  end

  test "issuing needs the date of supply the VAT Act asks for", %{admin: admin} do
    {:ok, draft} = Payments.create_invoice(Map.delete(attrs(), :supply_date), actor: admin)
    assert {:error, error} = Payments.issue_invoice(draft, actor: admin)
    assert Enum.any?(error.errors, &(&1.field == :supply_date))
    assert Ash.get!(Invoice, draft.id, authorize?: false).number == nil
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
