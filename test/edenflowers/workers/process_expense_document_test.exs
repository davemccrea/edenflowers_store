defmodule Edenflowers.Workers.ProcessExpenseDocumentTest do
  use Edenflowers.DataCase

  import ExUnit.CaptureLog
  import Mox

  alias Edenflowers.Expenses.Expense

  setup :verify_on_exit!

  @document_id "doc_abc123"
  @organization_id "org_xyz456"
  @job_args %{"document_id" => @document_id, "organization_id" => @organization_id}

  @file_response %{body: "PDF_BYTES", content_type: "application/pdf"}
  @extracted_fields %{
    "vendor_name" => "Acme Oy",
    "vendor_vat_number" => "FI12345678",
    "date" => "2026-05-15",
    "total_amount" => 121.0,
    "vat_amount" => 21.0,
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

    assert :ok = perform_job(Edenflowers.Workers.ProcessExpenseDocument, @job_args)

    expense = Ash.get!(Expense, [document_id: @document_id], authorize?: false)
    assert expense.vendor_name == "Acme Oy"
    assert expense.vendor_vat_number == "FI12345678"
    assert expense.date == ~D[2026-05-15]
    assert expense.total_amount == Decimal.new("121.0")
    assert expense.vat_amount == Decimal.new("21.0")
    assert expense.currency == :eur
    assert expense.category == :office_supplies
    assert expense.description == "Office chairs"
    assert expense.confidence == :high
    assert expense.document_id == @document_id
    assert expense.processed_at != nil
    assert expense.reviewed_at == nil
  end

  test "is idempotent: running the job twice does not create a duplicate expense" do
    stub(Edenflowers.Papra.Mock, :fetch_document, fn _, _ -> {:ok, @file_response} end)
    stub(Edenflowers.Claude.Mock, :extract_expense, fn _, _ -> {:ok, @extracted_fields} end)

    assert :ok = perform_job(Edenflowers.Workers.ProcessExpenseDocument, @job_args)
    assert :ok = perform_job(Edenflowers.Workers.ProcessExpenseDocument, @job_args)

    expenses = Ash.read!(Expense, authorize?: false)
    assert length(expenses) == 1
  end

  test "returns error when Papra fetch fails" do
    expect(Edenflowers.Papra.Mock, :fetch_document, fn _, _ ->
      {:error, {:papra_http_error, 404}}
    end)

    capture_log(fn ->
      assert {:error, _} = perform_job(Edenflowers.Workers.ProcessExpenseDocument, @job_args)
    end)

    assert Ash.read!(Expense, authorize?: false) == []
  end

  test "returns error when Claude extraction fails" do
    expect(Edenflowers.Papra.Mock, :fetch_document, fn _, _ -> {:ok, @file_response} end)

    expect(Edenflowers.Claude.Mock, :extract_expense, fn _, _ ->
      {:error, {:claude_extraction_failed, :timeout}}
    end)

    capture_log(fn ->
      assert {:error, _} = perform_job(Edenflowers.Workers.ProcessExpenseDocument, @job_args)
    end)

    assert Ash.read!(Expense, authorize?: false) == []
  end
end
