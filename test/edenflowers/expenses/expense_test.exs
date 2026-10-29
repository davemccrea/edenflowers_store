defmodule Edenflowers.Expenses.ExpenseTest do
  use Edenflowers.DataCase, async: true

  import ExUnit.CaptureLog
  import Mox

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
    test "upserts on document_id — re-ingesting updates extracted fields" do
      {:ok, _} = Expenses.ingest_expense(@valid_attrs, actor: system_actor())

      updated_attrs = Map.merge(@valid_attrs, %{vendor_name: "Acme Ab", confidence: "low"})
      {:ok, updated} = Expenses.ingest_expense(updated_attrs, actor: system_actor())

      assert updated.vendor_name == "Acme Ab"
      assert updated.confidence == :low

      assert [_single] = Ash.read!(Expense, authorize?: false)
    end

    test "accepts signed whole-cent amounts for credit notes" do
      attrs = Map.merge(@valid_attrs, %{document_id: "doc_credit", total_amount: "-12.50", vat_amount: "-2.50"})

      assert {:ok, expense} = Expenses.ingest_expense(attrs, actor: system_actor())
      assert Decimal.equal?(expense.total_amount, "-12.50")
      assert Decimal.equal?(expense.vat_amount, "-2.50")
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

    test "re-ingesting the document keeps the paid date" do
      {:ok, expense} = Expenses.ingest_expense(@valid_attrs, actor: system_actor())
      {:ok, _} = Expenses.correct_expense(expense, %{paid_on: "2026-06-02"}, actor: admin_actor())

      {:ok, reingested} =
        Expenses.ingest_expense(Map.put(@valid_attrs, :vendor_name, "Acme Ab"), actor: system_actor())

      assert reingested.vendor_name == "Acme Ab"
      assert reingested.paid_on == ~D[2026-06-02]
    end
  end

  describe "naming the Papra document" do
    setup do
      stub(Edenflowers.External.PapraAPI.Mock, :rename_document, fn document_id, name ->
        send(self(), {:renamed, document_id, name})
        :ok
      end)

      :ok
    end

    test "names it after the receipt date and vendor" do
      {:ok, _} = Expenses.ingest_expense(@valid_attrs, actor: system_actor())

      assert_received {:renamed, "doc_abc123", "2026-05-15 Acme Oy.pdf"}
    end

    test "waits until both the date and the vendor are known" do
      {:ok, expense} = Expenses.ingest_expense(Map.delete(@valid_attrs, :date), actor: system_actor())
      refute_received {:renamed, _, _}

      {:ok, _} = Expenses.correct_expense(expense, %{date: "2026-05-16"}, actor: admin_actor())
      assert_received {:renamed, "doc_abc123", "2026-05-16 Acme Oy.pdf"}
    end

    test "renames it again when the vendor is corrected, but not for other fields" do
      {:ok, expense} = Expenses.ingest_expense(@valid_attrs, actor: system_actor())
      assert_received {:renamed, _, _}

      {:ok, expense} = Expenses.correct_expense(expense, %{category: "travel"}, actor: admin_actor())
      refute_received {:renamed, _, _}

      {:ok, _} = Expenses.correct_expense(expense, %{vendor_name: "Kukkatukku Oy"}, actor: admin_actor())
      assert_received {:renamed, "doc_abc123", "2026-05-15 Kukkatukku Oy.pdf"}
    end

    test "still saves the expense when Papra can't rename it" do
      expect(Edenflowers.External.PapraAPI.Mock, :rename_document, fn _, _ -> {:error, {:papra_http_error, 500}} end)

      log =
        capture_log(fn ->
          assert {:ok, _} = Expenses.ingest_expense(@valid_attrs, actor: system_actor())
        end)

      assert log =~ "Failed to rename Papra document doc_abc123"
    end
  end

  describe "policies" do
    test "admin actor can read" do
      {:ok, expense} = Expenses.ingest_expense(@valid_attrs, actor: system_actor())
      assert {:ok, _} = Ash.get(Expense, expense.id, actor: admin_actor())
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
