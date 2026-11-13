defmodule Edenflowers.Bank.Actions.LinkReceipts do
  @moduledoc """
  Links each payment awaiting a receipt to an expense already paid by other
  means, mostly a card payment whose receipt arrived paid. Oldest payment
  first, each taking the earliest-paid candidate, so two payments of one amount
  in a week take one receipt each.
  """
  use Ash.Resource.Actions.Implementation

  alias Edenflowers.Bank
  alias Edenflowers.Expenses
  alias Edenflowers.Expenses.Expense

  @impl true
  def run(_input, _opts, context) do
    opts = Ash.Context.to_opts(context)

    with {:ok, transactions} <- Bank.bank_transactions_awaiting_receipt(opts) do
      transactions
      |> Enum.filter(&Expense.Currency.match?(&1.currency))
      |> Enum.reduce_while(:ok, fn transaction, :ok -> link(transaction, opts) end)
    end
  end

  defp link(transaction, opts) do
    result =
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

    case result do
      {:error, error} -> {:halt, {:error, error}}
      _linked_or_not -> {:cont, :ok}
    end
  end
end
