defmodule Edenflowers.Expenses.ExpenseTest do
  use Edenflowers.DataCase, async: true

  alias Edenflowers.Expenses.Expense

  alias Edenflowers.Expenses

  @valid_attrs %{
    document_id: "doc_abc123",
    vendor_name: "Acme Oy",
    vendor_vat_number: "FI12345678",
    date: "2026-05-15",
    total_amount: "121.00",
    vat_amount: "21.00",
    currency: "eur",
    category: "office_supplies",
    description: "Office chairs",
    confidence: "high"
  }

  describe ":ingest" do
    test "creates an expense with all fields coerced to the correct types" do
      assert {:ok, expense} = Expenses.ingest_expense(@valid_attrs, actor: system_actor())

      assert expense.document_id == "doc_abc123"
      assert expense.vendor_name == "Acme Oy"
      assert expense.date == ~D[2026-05-15]
      assert expense.total_amount == Decimal.new("121.00")
      assert expense.vat_amount == Decimal.new("21.00")
      assert expense.currency == :eur
      assert expense.category == :office_supplies
      assert expense.confidence == :high
      assert expense.processed_at != nil
      assert expense.reviewed_at == nil
    end

    test "upserts on document_id — re-ingesting updates extracted fields" do
      {:ok, _} = Expenses.ingest_expense(@valid_attrs, actor: system_actor())

      updated_attrs = Map.merge(@valid_attrs, %{vendor_name: "Acme Ab", confidence: "low"})
      {:ok, updated} = Expenses.ingest_expense(updated_attrs, actor: system_actor())

      assert updated.vendor_name == "Acme Ab"
      assert updated.confidence == :low

      assert [_single] = Ash.read!(Expense, authorize?: false)
    end

    test "accepts null for optional fields" do
      minimal = %{document_id: "doc_minimal", confidence: "medium"}
      assert {:ok, expense} = Expenses.ingest_expense(minimal, actor: system_actor())

      assert expense.vendor_name == nil
      assert expense.date == nil
      assert expense.total_amount == nil
      assert expense.currency == nil
      assert expense.category == nil
    end

    test "requires document_id" do
      assert {:error, error} =
               Expenses.ingest_expense(Map.delete(@valid_attrs, :document_id), actor: system_actor())

      assert error
             |> Ash.Error.to_ash_error()
             |> Map.fetch!(:errors)
             |> Enum.any?(fn e ->
               Map.get(e, :field) == :document_id
             end)
    end

    test "requires confidence" do
      assert {:error, _} =
               Expenses.ingest_expense(Map.delete(@valid_attrs, :confidence), actor: system_actor())
    end

    test "rejects an unknown category value" do
      assert {:error, _} =
               Expenses.ingest_expense(Map.put(@valid_attrs, :category, "invalid_cat"), actor: system_actor())
    end

    test "rejects an unknown currency value" do
      assert {:error, _} =
               Expenses.ingest_expense(Map.put(@valid_attrs, :currency, "usd"), actor: system_actor())
    end

    test "accepts signed whole-cent amounts for credit notes" do
      attrs = Map.merge(@valid_attrs, %{document_id: "doc_credit", total_amount: "-12.50", vat_amount: "-2.50"})

      assert {:ok, expense} = Expenses.ingest_expense(attrs, actor: system_actor())
      assert Decimal.equal?(expense.total_amount, "-12.50")
      assert Decimal.equal?(expense.vat_amount, "-2.50")
    end

    test "rejects fractional-cent amounts" do
      assert {:error, _} =
               Expenses.ingest_expense(Map.put(@valid_attrs, :total_amount, "12.345"), actor: system_actor())
    end
  end

  describe ":mark_reviewed" do
    test "sets reviewed_at to the current time" do
      {:ok, expense} = Expenses.ingest_expense(@valid_attrs, actor: system_actor())
      assert expense.reviewed_at == nil

      {:ok, reviewed} = Expenses.mark_expense_reviewed(expense, actor: admin_actor())
      assert reviewed.reviewed_at != nil
    end

    test "a draft missing its date, vendor, total or currency is stored but can't be saved or reviewed until filled in" do
      draft = Map.drop(@valid_attrs, [:date, :vendor_name, :total_amount, :currency])
      {:ok, expense} = Expenses.ingest_expense(draft, actor: system_actor())

      assert {:error, %{errors: errors}} = Expenses.mark_expense_reviewed(expense, actor: admin_actor())
      assert errors |> Enum.map(& &1.field) |> Enum.sort() == [:currency, :date, :total_amount, :vendor_name]

      assert {:error, _} = Expenses.correct_expense(expense, %{vendor_name: "Acme Oy"}, actor: admin_actor())

      complete = %{date: "2026-06-01", vendor_name: "Acme Oy", total_amount: "12.40", currency: :eur}
      assert {:ok, _} = Expenses.correct_expense(expense, complete, actor: admin_actor())
    end
  end

  describe ":correct" do
    test "updates the extracted fields" do
      {:ok, expense} = Expenses.ingest_expense(@valid_attrs, actor: system_actor())

      {:ok, corrected} =
        Expenses.correct_expense(
          expense,
          %{vendor_name: "Corrected Vendor", category: "travel"},
          actor: admin_actor()
        )

      assert corrected.vendor_name == "Corrected Vendor"
      assert corrected.category == :travel
      assert corrected.document_id == expense.document_id
    end

    test "sets and clears the paid date" do
      {:ok, expense} = Expenses.ingest_expense(@valid_attrs, actor: system_actor())

      {:ok, paid} = Expenses.correct_expense(expense, %{paid_on: "2026-06-02"}, actor: admin_actor())
      assert paid.paid_on == ~D[2026-06-02]

      {:ok, cleared} = Expenses.correct_expense(paid, %{paid_on: nil}, actor: admin_actor())
      assert cleared.paid_on == nil
    end

    test "re-ingesting the document keeps the paid date" do
      {:ok, expense} = Expenses.ingest_expense(@valid_attrs, actor: system_actor())
      {:ok, _} = Expenses.correct_expense(expense, %{paid_on: "2026-06-02"}, actor: admin_actor())

      {:ok, reingested} =
        Expenses.ingest_expense(Map.put(@valid_attrs, :vendor_name, "Acme Ab"), actor: system_actor())

      assert reingested.vendor_name == "Acme Ab"
      assert reingested.paid_on == ~D[2026-06-02]
    end
  end

  describe "policies" do
    test "system actor can ingest" do
      assert {:ok, _} = Expenses.ingest_expense(@valid_attrs, actor: system_actor())
    end

    test "admin actor can read" do
      {:ok, expense} = Expenses.ingest_expense(@valid_attrs, actor: system_actor())
      assert {:ok, _} = Ash.get(Expense, expense.id, actor: admin_actor())
    end

    test "admin actor can mark_reviewed and correct" do
      {:ok, expense} = Expenses.ingest_expense(@valid_attrs, actor: system_actor())
      assert {:ok, _} = Expenses.mark_expense_reviewed(expense, actor: admin_actor())
      assert {:ok, _} = Expenses.correct_expense(expense, %{vendor_name: "X"}, actor: admin_actor())
    end

    test "unauthenticated actor cannot read" do
      {:ok, expense} = Expenses.ingest_expense(@valid_attrs, actor: system_actor())
      assert {:error, _} = Ash.get(Expense, expense.id, actor: nil)
    end

    test "unauthenticated actor cannot ingest" do
      assert {:error, _} = Expenses.ingest_expense(@valid_attrs, actor: nil)
    end
  end

  defp system_actor, do: %{system: true}
  defp admin_actor, do: %{admin: true}
end
