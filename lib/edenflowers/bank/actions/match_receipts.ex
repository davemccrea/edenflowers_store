defmodule Edenflowers.Bank.Actions.MatchReceipts do
  @moduledoc """
  Matches the stored payments still awaiting a receipt to expenses, as the bank
  sync does with the payments it reads, so a receipt arriving after its payment
  is matched at once rather than at the next sync.

  First each payment settles the unpaid expense it pays. Then each one left
  links to an expense already paid by other means, mostly a card payment whose
  receipt arrived paid. Settling comes first so a payment quoting no reference
  still sees the expenses paid by hand that week, before linking claims them.
  Oldest payment first, each taking the earliest-paid candidate, so two
  payments of one amount in a week take one receipt each.
  """
  use Ash.Resource.Actions.Implementation

  alias Edenflowers.Bank
  alias Edenflowers.Expenses
  alias Edenflowers.Expenses.Expense

  @impl true
  def run(_input, _opts, context) do
    opts = Ash.Context.to_opts(context)

    with :ok <- each_awaiting(&settle(&1, opts), opts) do
      each_awaiting(&link(&1, opts), opts)
    end
  end

  defp each_awaiting(fun, opts) do
    with {:ok, transactions} <- Bank.bank_transactions_awaiting_receipt(opts) do
      transactions
      |> Enum.filter(&Expense.Currency.match?(&1.currency))
      |> Enum.reduce_while(:ok, fn transaction, :ok -> halt_on_error(fun.(transaction)) end)
    end
  end

  defp halt_on_error({:error, error}), do: {:halt, {:error, error}}
  defp halt_on_error(_matched_or_not), do: {:cont, :ok}

  defp settle(transaction, opts) do
    Expenses.settle_expense_from_bank(
      transaction.reference_number,
      transaction.amount,
      transaction.currency,
      transaction.booked_on,
      %{bank_transaction_id: transaction.bank_id},
      opts
    )
  end

  defp link(transaction, opts) do
    with {:ok, [expense | _]} <-
           Expenses.expenses_paid_near_bank_payment(
             transaction.bank_id,
             transaction.amount,
             transaction.currency,
             transaction.booked_on,
             opts
           ) do
      Expenses.link_expense_bank_payment(expense, transaction.booked_on, transaction.bank_id, opts)
    end
  end
end
