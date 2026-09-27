defmodule Edenflowers.Expenses.ExpenseImportTest do
  use Edenflowers.DataCase

  import ExUnit.CaptureLog
  import Mox

  alias Edenflowers.Expenses.Expense
  alias Edenflowers.Expenses.ExpenseImport
  alias Edenflowers.Expenses.ExpenseImport.Workers.Process

  setup :verify_on_exit!

  @document_id "doc_abc123"
  @organization_id "org_xyz456"

  @file_response %{body: "PDF_BYTES", content_type: "application/pdf"}
  @extracted_fields %{
    "vendor_name" => "Acme Oy",
    "vendor_vat_number" => "FI12345678",
    "date" => "2026-05-15",
    "total_amount" => "121.00",
    "vat_amount" => "21.00",
    "currency" => "eur",
    "category" => "office_supplies",
    "description" => "Office chairs",
    "confidence" => "high"
  }

  test "fetches the document, extracts fields, and ingests the expense" do
    expect(Edenflowers.Papra.Mock, :fetch_document, fn @organization_id, @document_id ->
      {:ok, @file_response}
    end)

    expect(Edenflowers.Claude.Mock, :extract_expense, fn "PDF_BYTES", "application/pdf" ->
      {:ok, @extracted_fields}
    end)

    import = record_import()
    assert {:ok, _import} = process(import)

    expense = Ash.get!(Expense, [document_id: @document_id], authorize?: false)
    assert expense.vendor_name == "Acme Oy"
    assert expense.vendor_vat_number == "FI12345678"
    assert expense.date == ~D[2026-05-15]
    assert expense.total_amount == Decimal.new("121.00")
    assert expense.vat_amount == Decimal.new("21.00")
    assert expense.currency == :eur
    assert expense.category == :office_supplies
    assert expense.description == "Office chairs"
    assert expense.confidence == :high
    assert expense.document_id == @document_id
    assert expense.processed_at != nil
    assert expense.reviewed_at == nil

    import = Ash.get!(ExpenseImport, import.id, authorize?: false)
    assert import.processed_at
    assert import.expense_id == expense.id
  end

  test "recording the same document twice processes it once" do
    expect(Edenflowers.Papra.Mock, :fetch_document, fn _, _ -> {:ok, @file_response} end)
    expect(Edenflowers.Claude.Mock, :extract_expense, fn _, _ -> {:ok, @extracted_fields} end)

    import = record_import()
    assert {:ok, _import} = process(import)

    assert record_import().id == import.id
    assert {:cancel, :trigger_no_longer_applies} = process(import)

    assert [_expense] = Ash.read!(Expense, authorize?: false)
  end

  test "fails the job when Papra fetch fails" do
    expect(Edenflowers.Papra.Mock, :fetch_document, fn _, _ ->
      {:error, {:papra_http_error, 404}}
    end)

    capture_log(fn ->
      assert_raise Ash.Error.Invalid, fn -> process(record_import()) end
    end)

    assert Ash.read!(Expense, authorize?: false) == []
  end

  test "fails the job when Claude extraction fails" do
    expect(Edenflowers.Papra.Mock, :fetch_document, fn _, _ -> {:ok, @file_response} end)

    expect(Edenflowers.Claude.Mock, :extract_expense, fn _, _ ->
      {:error, {:claude_extraction_failed, :timeout}}
    end)

    capture_log(fn ->
      assert_raise Ash.Error.Invalid, fn -> process(record_import()) end
    end)

    assert Ash.read!(Expense, authorize?: false) == []
  end

  defp record_import do
    {:ok, import} =
      Edenflowers.Expenses.record_expense_import(
        %{document_id: @document_id, organization_id: @organization_id},
        actor: Edenflowers.Actors.system_actor()
      )

    import
  end

  defp process(import), do: perform_job(Process, %{"primary_key" => %{"id" => import.id}})
end
