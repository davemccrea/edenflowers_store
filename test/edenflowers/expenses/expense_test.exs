defmodule Edenflowers.Expenses.ExpenseTest do
  use Edenflowers.DataCase

  alias Edenflowers.Expenses.Expense

  @valid_attrs %{
    document_id: "doc_abc123",
    vendor_name: "Acme Oy",
    vendor_vat_number: "FI12345678",
    date: "2026-05-15",
    total_amount: 121.0,
    vat_amount: 21.0,
    currency: "eur",
    category: "office_supplies",
    description: "Office chairs",
    confidence: "high"
  }

  describe ":ingest" do
    test "creates an expense with all fields coerced to the correct types" do
      assert {:ok, expense} = Expense.ingest(@valid_attrs, actor: system_actor())

      assert expense.document_id == "doc_abc123"
      assert expense.vendor_name == "Acme Oy"
      assert expense.date == ~D[2026-05-15]
      assert expense.total_amount == Decimal.new("121.0")
      assert expense.vat_amount == Decimal.new("21.0")
      assert expense.currency == :eur
      assert expense.category == :office_supplies
      assert expense.confidence == :high
      assert expense.processed_at != nil
      assert expense.reviewed_at == nil
    end

    test "upserts on document_id — re-ingesting updates extracted fields" do
      {:ok, _} = Expense.ingest(@valid_attrs, actor: system_actor())

      updated_attrs = Map.merge(@valid_attrs, %{vendor_name: "Acme Ab", confidence: "low"})
      {:ok, updated} = Expense.ingest(updated_attrs, actor: system_actor())

      assert updated.vendor_name == "Acme Ab"
      assert updated.confidence == :low

      assert [_single] = Ash.read!(Expense, authorize?: false)
    end

    test "accepts null for optional fields" do
      minimal = %{document_id: "doc_minimal", confidence: "medium"}
      assert {:ok, expense} = Expense.ingest(minimal, actor: system_actor())

      assert expense.vendor_name == nil
      assert expense.date == nil
      assert expense.total_amount == nil
      assert expense.currency == nil
      assert expense.category == nil
    end

    test "requires document_id" do
      assert {:error, error} =
               Expense.ingest(Map.delete(@valid_attrs, :document_id), actor: system_actor())

      assert error
             |> Ash.Error.to_ash_error()
             |> Map.get(:errors)
             |> Enum.any?(fn e ->
               Map.get(e, :field) == :document_id
             end)
    end

    test "requires confidence" do
      assert {:error, _} =
               Expense.ingest(Map.delete(@valid_attrs, :confidence), actor: system_actor())
    end

    test "rejects an unknown category value" do
      assert {:error, _} =
               Expense.ingest(Map.put(@valid_attrs, :category, "invalid_cat"), actor: system_actor())
    end

    test "rejects an unknown currency value" do
      assert {:error, _} =
               Expense.ingest(Map.put(@valid_attrs, :currency, "usd"), actor: system_actor())
    end
  end

  describe ":mark_reviewed" do
    test "sets reviewed_at to the current time" do
      {:ok, expense} = Expense.ingest(@valid_attrs, actor: system_actor())
      assert expense.reviewed_at == nil

      {:ok, reviewed} = Expense.mark_reviewed(expense, actor: admin_actor())
      assert reviewed.reviewed_at != nil
    end
  end

  describe ":correct" do
    test "updates the extracted fields" do
      {:ok, expense} = Expense.ingest(@valid_attrs, actor: system_actor())

      {:ok, corrected} =
        Expense.correct(
          expense,
          %{vendor_name: "Corrected Vendor", category: "travel"},
          actor: admin_actor()
        )

      assert corrected.vendor_name == "Corrected Vendor"
      assert corrected.category == :travel
      assert corrected.document_id == expense.document_id
    end
  end

  describe "policies" do
    test "system actor can ingest" do
      assert {:ok, _} = Expense.ingest(@valid_attrs, actor: system_actor())
    end

    test "admin actor can read" do
      {:ok, expense} = Expense.ingest(@valid_attrs, actor: system_actor())
      assert {:ok, _} = Ash.get(Expense, expense.id, actor: admin_actor())
    end

    test "admin actor can mark_reviewed and correct" do
      {:ok, expense} = Expense.ingest(@valid_attrs, actor: system_actor())
      assert {:ok, _} = Expense.mark_reviewed(expense, actor: admin_actor())
      assert {:ok, _} = Expense.correct(expense, %{vendor_name: "X"}, actor: admin_actor())
    end

    test "unauthenticated actor cannot read" do
      {:ok, expense} = Expense.ingest(@valid_attrs, actor: system_actor())
      assert {:error, _} = Ash.get(Expense, expense.id, actor: nil)
    end

    test "unauthenticated actor cannot ingest" do
      assert {:error, _} = Expense.ingest(@valid_attrs, actor: nil)
    end
  end

  defp system_actor, do: %{system: true}
  defp admin_actor, do: %{admin: true}
end
