defmodule Edenflowers.Bank.MissingReceiptsTest do
  use Edenflowers.DataCase, async: true

  import Edenflowers.Actors

  alias Edenflowers.Bank
  alias Edenflowers.Expenses
  alias Edenflowers.Expenses.Expense
  alias Edenflowers.External.EnableBankingAPI

  @admin %{admin: true}

  test "every payment out is kept once, and one paid by a card receipt links to it without changing its date" do
    connect()
    booked_on = days_ago(2)
    receipt = seed_expense(total_amount: Decimal.new("12.40"), paid_on: days_ago(3))
    stub_transactions([payment("tx-1", "12.40", booked_on), payment("tx-2", "55.00", booked_on)])

    Bank.sync_bank_payments!(actor: system_actor())
    Bank.sync_bank_payments!(actor: system_actor())

    assert Ash.read!(Bank.Transaction, authorize?: false) |> Enum.map(& &1.bank_id) |> Enum.sort() == ["tx-1", "tx-2"]
    assert %{bank_transaction_id: "tx-1", paid_on: paid_on} = reload(receipt)
    assert paid_on == days_ago(3)
  end

  test "two card payments of one amount in a week take one receipt each" do
    connect()
    first = seed_expense(total_amount: Decimal.new("9.90"), paid_on: days_ago(6))
    second = seed_expense(total_amount: Decimal.new("9.90"), paid_on: days_ago(3))
    stub_transactions([payment("tx-late", "9.90", days_ago(2)), payment("tx-early", "9.90", days_ago(5))])

    Bank.sync_bank_payments!(actor: system_actor())

    assert reload(first).bank_transaction_id == "tx-early"
    assert reload(second).bank_transaction_id == "tx-late"
  end

  test "a receipt paid over a week from the booking, or in another amount, isn't linked" do
    connect()
    long_before = seed_expense(total_amount: Decimal.new("20.00"), paid_on: days_ago(12))
    other_amount = seed_expense(total_amount: Decimal.new("21.00"), paid_on: days_ago(2))
    stub_transactions([payment("tx-1", "20.00", days_ago(2))])

    Bank.sync_bank_payments!(actor: system_actor())

    assert Enum.map([long_before, other_amount], &reload(&1).bank_transaction_id) == [nil, nil]
  end

  test "a scheduled expense isn't a paid receipt, so a payment quoting no reference doesn't link to one of two" do
    connect()
    first = seed_expense(total_amount: Decimal.new("50.00"), paid_on: days_ago(-1))
    second = seed_expense(total_amount: Decimal.new("50.00"), paid_on: days_ago(-3))
    stub_transactions([payment("tx-1", "50.00", days_ago(1))])

    Bank.sync_bank_payments!(actor: system_actor())

    assert Enum.map([first, second], &reload(&1).bank_transaction_id) == [nil, nil]
  end

  describe "the payments missing a receipt" do
    test "are those booked over a week ago, or in a month that has ended, paying no expense and not dismissed" do
      today = Edenflowers.ShopTime.today()
      last_month = Date.add(Date.beginning_of_month(today), -1)

      old = seed_transaction("old", days_ago(8))
      ended_month = seed_transaction("ended-month", last_month)
      seed_transaction("this-week", today)
      dismissed = seed_transaction("dismissed", days_ago(10))
      Bank.dismiss_bank_payment!(dismissed, actor: @admin)
      paid = seed_transaction("paid", days_ago(10))
      seed_expense(paid_on: days_ago(10), bank_transaction_id: "paid")

      missing = Bank.bank_payments_missing_receipt!(actor: @admin) |> Enum.map(& &1.bank_id) |> Enum.sort()

      assert missing == Enum.sort([old.bank_id, ended_month.bank_id])
      refute paid.bank_id in missing
    end

    test "include one whose expense Jennie marked unpaid after a wrong match" do
      transaction = seed_transaction("wrong", days_ago(10))
      expense = seed_expense(paid_on: days_ago(10), bank_transaction_id: "wrong")

      Expenses.mark_expense_unpaid!(expense, actor: @admin)

      assert [%{id: id}] = Bank.bank_payments_missing_receipt!(actor: @admin)
      assert id == transaction.id
    end

    test "lose the real payment once it pays the expense a wrong match left, and keep the wrong one" do
      wrong = seed_transaction("wrong", days_ago(10))
      seed_transaction("real", days_ago(9))
      expense = seed_expense(paid_on: days_ago(10), bank_transaction_id: "wrong")
      Expenses.mark_expense_unpaid!(expense, actor: @admin)

      Expenses.mark_expense_paid_from_bank!(reload(expense), days_ago(9), %{bank_transaction_id: "real"},
        actor: system_actor()
      )

      assert [%{id: id}] = Bank.bank_payments_missing_receipt!(actor: @admin)
      assert id == wrong.id
    end

    test "lose one Jennie dismisses and get it back when she restores it" do
      transaction = seed_transaction("fee", days_ago(10))

      transaction = Bank.dismiss_bank_payment!(transaction, actor: @admin)
      assert Bank.bank_payments_missing_receipt!(actor: @admin) == []
      assert [_dismissed] = Bank.dismissed_bank_payments!(actor: @admin)

      Bank.restore_bank_payment!(transaction, actor: @admin)
      assert [_missing] = Bank.bank_payments_missing_receipt!(actor: @admin)
    end
  end

  describe "linking by hand" do
    test "offers unlinked expenses dated within 30 days, closest amount first" do
      booked_on = days_ago(10)
      closest = seed_expense(total_amount: Decimal.new("49.00"), date: booked_on)
      further = seed_expense(total_amount: Decimal.new("60.00"), date: Date.add(booked_on, 29))
      seed_expense(total_amount: Decimal.new("50.00"), date: Date.add(booked_on, -31))
      seed_expense(total_amount: Decimal.new("50.00"), date: booked_on, bank_transaction_id: "other")

      offered = Expenses.expenses_linkable_by_hand!(booked_on, Decimal.new("50.00"), actor: @admin)

      assert Enum.map(offered, & &1.id) == [closest.id, further.id]
    end

    test "marks an unpaid expense paid on the booking date and leaves a paid one's date" do
      unpaid = seed_expense([])
      paid = seed_expense(paid_on: days_ago(20))

      assert %{paid_on: paid_on} = Expenses.link_expense_bank_payment!(unpaid, days_ago(10), "tx-1", actor: @admin)
      assert paid_on == days_ago(10)

      assert %{paid_on: paid_on} = Expenses.link_expense_bank_payment!(paid, days_ago(10), "tx-2", actor: @admin)
      assert paid_on == days_ago(20)
    end

    test "won't take an expense another payment linked since the picker loaded" do
      expense = seed_expense(paid_on: days_ago(20))
      Expenses.link_expense_bank_payment!(expense, days_ago(10), "tx-1", actor: system_actor())

      assert {:error, _} = Expenses.link_expense_bank_payment(expense, days_ago(10), "tx-2", actor: @admin)
      assert reload(expense).bank_transaction_id == "tx-1"
    end
  end

  test "an unlinked payment misses its receipt again, keeps the expense's date and never links to it again" do
    connect()
    receipt = seed_expense(total_amount: Decimal.new("12.40"), paid_on: days_ago(10))
    invoice = seed_expense(total_amount: Decimal.new("12.40"), date: days_ago(20))
    stub_transactions([payment("tx-1", "12.40", days_ago(9))])
    Bank.sync_bank_payments!(actor: system_actor())
    assert reload(receipt).bank_transaction_id == "tx-1"

    Expenses.unlink_expense_bank_payment!(reload(receipt), actor: @admin)
    Bank.sync_bank_payments!(actor: system_actor())

    assert %{bank_transaction_id: nil, paid_on: paid_on} = reload(receipt)
    assert paid_on == days_ago(10)
    assert reload(invoice).paid_on == nil
    assert [%{bank_id: "tx-1"}] = Bank.bank_payments_missing_receipt!(actor: @admin)
  end

  defp days_ago(days), do: Date.add(Edenflowers.ShopTime.today(), -days)

  defp connect do
    Ash.Seed.seed!(Bank.Connection, %{
      session_id: "session-1",
      account_ids: ["account-1"],
      valid_until: DateTime.add(DateTime.utc_now(), 90, :day)
    })
  end

  defp seed_expense(attrs) do
    defaults = %{
      document_id: "doc-#{System.unique_integer([:positive])}",
      vendor_name: "Kahvila Kukka",
      total_amount: Decimal.new("100.00"),
      currency: :eur,
      confidence: :high,
      processed_at: DateTime.utc_now()
    }

    Ash.Seed.seed!(Expense, Map.merge(defaults, Map.new(attrs)))
  end

  defp seed_transaction(bank_id, booked_on) do
    Ash.Seed.seed!(Bank.Transaction, %{
      bank_id: bank_id,
      booked_on: booked_on,
      amount: Decimal.new("10.00"),
      currency: "eur"
    })
  end

  defp reload(expense), do: Ash.get!(Expense, expense.id, authorize?: false)

  defp payment(id, amount, booked_on) do
    %{
      "entry_reference" => id,
      "credit_debit_indicator" => "DBIT",
      "transaction_amount" => %{"amount" => amount, "currency" => "EUR"},
      "booking_date" => Date.to_iso8601(booked_on),
      "status" => "BOOK",
      "creditor" => %{"name" => "Kahvila Kukka"}
    }
  end

  defp stub_transactions(transactions) do
    Req.Test.stub(EnableBankingAPI, fn
      %{request_path: "/accounts/account-1/transactions"} = conn ->
        Req.Test.json(conn, %{"transactions" => transactions, "continuation_key" => nil})

      %{request_path: "/accounts/account-1/balances"} = conn ->
        Req.Test.json(conn, %{"balances" => []})
    end)
  end
end
