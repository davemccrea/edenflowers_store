defmodule Edenflowers.Bank.SyncPaymentsTest do
  # Issuing an invoice holds the number series lock until the test ends, so the
  # modules that issue one take turns; sharing any unique value could deadlock them.
  use Edenflowers.DataCase, async: true, group: :invoice_numbers

  import Edenflowers.Actors
  import Mox

  alias Edenflowers.Bank
  alias Edenflowers.Expenses
  alias Edenflowers.Expenses.Expense
  alias Edenflowers.External.EnableBankingAPI
  alias Edenflowers.Payments

  setup :verify_on_exit!

  test "a payment matching reference, amount and currency marks the expense paid on its booking date" do
    connect()
    expense = seed_expense(reference_number: "123453", total_amount: Decimal.new("875.00"))
    stub_transactions([payment("875.00", "00000000000000123453", "2026-11-03")])

    assert :ok = Bank.sync_bank_payments(actor: system_actor())

    assert reload(expense).paid_on == ~D[2026-11-03]
  end

  test "a booked payment replaces the date Jennie scheduled it for" do
    connect()
    scheduled_for = Date.add(Date.utc_today(), 5)
    booked_on = Date.utc_today() |> Date.add(-1) |> Date.to_iso8601()
    expense = seed_expense(reference_number: "123453", paid_on: scheduled_for)
    stub_transactions([payment("100.00", "123453", booked_on)])

    Bank.sync_bank_payments!(actor: system_actor())

    assert Date.to_iso8601(reload(expense).paid_on) == booked_on
  end

  test "a payment of a different amount, or matching several expenses, leaves them unpaid" do
    connect()
    different = seed_expense(reference_number: "123453", total_amount: Decimal.new("99.00"))
    twin_a = seed_expense(reference_number: "222228", document_id: "doc-a")
    twin_b = seed_expense(reference_number: "222228", document_id: "doc-b")
    stub_transactions([payment("100.00", "123453", "2026-11-03"), payment("100.00", "222228", "2026-11-03")])

    Bank.sync_bank_payments!(actor: system_actor())

    assert Enum.map([different, twin_a, twin_b], &reload(&1).paid_on) == [nil, nil, nil]
  end

  test "money arriving never settles an expense" do
    connect()
    expense = seed_expense(reference_number: "123453")
    stub_transactions([%{payment("100.00", "123453", "2026-11-03") | "credit_debit_indicator" => "CRDT"}])

    Bank.sync_bank_payments!(actor: system_actor())

    assert reload(expense).paid_on == nil
  end

  test "reads nothing before the bank is connected or once the consent has ended" do
    Req.Test.stub(EnableBankingAPI, fn _conn -> flunk("Enable Banking was called") end)
    assert :ok = Bank.sync_bank_payments(actor: system_actor())

    connect(DateTime.add(DateTime.utc_now(), -1, :day))
    assert :ok = Bank.sync_bank_payments(actor: system_actor())
  end

  describe "transfers in" do
    setup do
      connect()
      %{invoice: issue_invoice(), today: Edenflowers.ShopTime.today() |> Date.to_iso8601()}
    end

    test "one quoting an open invoice's reference is recorded as its payment, once", %{invoice: invoice, today: today} do
      stub_transactions([transfer("100.00", invoice.reference_number, today)])

      Bank.sync_bank_payments!(actor: system_actor())
      Bank.sync_bank_payments!(actor: system_actor())

      invoice = Ash.load!(invoice, [:status, :payments], authorize?: false)
      assert invoice.status == :paid
      assert [%{amount: amount, paid_at: paid_at}] = invoice.payments
      assert Decimal.equal?(amount, "100.00")
      assert Date.to_iso8601(Edenflowers.ShopTime.today(paid_at)) == today
    end

    test "a part payment is recorded and leaves the rest owed", %{invoice: invoice, today: today} do
      stub_transactions([transfer("50.00", invoice.reference_number, today)])

      Bank.sync_bank_payments!(actor: system_actor())

      invoice = Ash.load!(invoice, [:status, :amount_unpaid], authorize?: false)
      assert invoice.status == :open
      assert Decimal.equal?(invoice.amount_unpaid, "50.00")
    end

    test "an overpayment or an unknown reference is left for Jennie", %{invoice: invoice, today: today} do
      stub_transactions([
        transfer("200.00", invoice.reference_number, today),
        transfer("100.00", "123453", today)
      ])

      Bank.sync_bank_payments!(actor: system_actor())

      assert Ash.load!(invoice, :status, authorize?: false).status == :open
    end

    test "one booked before the invoice was issued is left alone", %{invoice: invoice} do
      yesterday = Edenflowers.ShopTime.today() |> Date.add(-1) |> Date.to_iso8601()
      stub_transactions([transfer("100.00", invoice.reference_number, yesterday)])

      Bank.sync_bank_payments!(actor: system_actor())

      assert Ash.load!(invoice, :status, authorize?: false).status == :open
    end
  end

  test "an invoice's reference is stored the way the bank sends it" do
    stub(Edenflowers.External.PapraAPI.Mock, :update_document, fn _, _ -> :ok end)

    {:ok, expense} =
      Expenses.ingest_expense(
        %{document_id: "doc-ref", confidence: "high", reference_number: " 0012 3453 "},
        actor: system_actor()
      )

    assert expense.reference_number == "123453"
  end

  defp connect(valid_until \\ DateTime.add(DateTime.utc_now(), 90, :day)) do
    Ash.Seed.seed!(Bank.Connection, %{session_id: "session-1", account_ids: ["account-1"], valid_until: valid_until})
  end

  defp seed_expense(attrs) do
    defaults = %{
      document_id: "doc-#{System.unique_integer([:positive])}",
      vendor_name: "Pohjanmaan Kukkutukku",
      total_amount: Decimal.new("100.00"),
      currency: :eur,
      confidence: :high,
      processed_at: DateTime.utc_now()
    }

    Ash.Seed.seed!(Expense, Map.merge(defaults, Map.new(attrs)))
  end

  defp reload(expense), do: Ash.get!(Expense, expense.id, authorize?: false)

  defp payment(amount, reference, booking_date) do
    %{
      "entry_reference" => "tx-#{reference}-#{amount}",
      "credit_debit_indicator" => "DBIT",
      "transaction_amount" => %{"amount" => amount, "currency" => "EUR"},
      "booking_date" => booking_date,
      "status" => "BOOK",
      "reference_number" => reference
    }
  end

  defp transfer(amount, reference, booking_date),
    do: %{payment(amount, reference, booking_date) | "credit_debit_indicator" => "CRDT"}

  # Unit prices include VAT: 100 € owed.
  defp issue_invoice do
    admin = %{admin: true}

    {:ok, draft} =
      Payments.create_invoice(
        %{
          buyer_name: "Hääpari",
          buyer_email: "buyer@example.com",
          supply_date: ~D[2026-11-02],
          lines: [%{description: "Wedding flowers", quantity: "1", unit_price: "100", vat_rate: "25.5"}]
        },
        actor: admin
      )

    Payments.issue_invoice!(draft, actor: admin)
  end

  defp stub_transactions(transactions) do
    Req.Test.stub(EnableBankingAPI, fn %{request_path: "/accounts/account-1/transactions"} = conn ->
      Req.Test.json(conn, %{"transactions" => transactions, "continuation_key" => nil})
    end)
  end
end
