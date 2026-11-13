defmodule Edenflowers.Expenses.Actions.SettleExpenseFromBank do
  @moduledoc """
  Marks paid the one expense a booked bank payment settles.

  A payment quoting a reference settles the expense with that reference,
  amount and currency. One quoting none, as when Jennie pays without typing
  the reference, settles the only expense of its amount and currency dated in
  the 60 days up to the booking. The sync re-reads the same payments for two
  weeks, so the expense keeps the payment's id and a payment that has settled
  one expense, or that Jennie unlinked from one, never settles another of the
  same amount.

  Most payments quoting no reference are card payments whose receipt arrived
  already paid, or ones Jennie marked paid herself. Such a payment settles
  nothing, or it would mark paid some other expense of the same amount.
  """
  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias Edenflowers.Expenses
  alias Edenflowers.Expenses.Expense
  alias Edenflowers.Payments.ReferenceNumber

  @impl true
  def run(input, _opts, context) do
    arguments = input.arguments
    transaction_id = arguments.bank_transaction_id
    opts = Ash.Context.to_opts(context)

    reference = ReferenceNumber.normalize(arguments[:reference_number])

    with {:ok, [expense]} <- candidates(reference, arguments, opts),
         {:ok, _expense} <-
           Expenses.mark_expense_paid_from_bank(
             expense,
             arguments.booked_on,
             %{bank_transaction_id: transaction_id, matched_by_amount: is_nil(reference)},
             opts
           ) do
      {:ok, true}
    else
      {:error, error} -> {:error, error}
      _no_single_match -> {:ok, false}
    end
  end

  defp candidates(reference, arguments, opts) when is_binary(reference) do
    Expenses.expenses_awaiting_bank_payment(reference, arguments.amount, arguments.currency, opts)
  end

  defp candidates(nil, %{bank_transaction_id: transaction_id} = arguments, opts) do
    if settled_an_expense?(transaction_id, opts) or pays_an_expense_already_paid?(arguments, opts) do
      :settles_nothing
    else
      Expenses.expenses_awaiting_unreferenced_bank_payment(
        arguments.amount,
        arguments.currency,
        arguments.booked_on,
        opts
      )
    end
  end

  defp settled_an_expense?(transaction_id, opts) do
    Expense
    |> Ash.Query.filter(
      bank_transaction_id == ^transaction_id or
        fragment("? = ANY(?)", ^transaction_id, unlinked_bank_transaction_ids)
    )
    |> Ash.exists?(opts)
  end

  defp pays_an_expense_already_paid?(arguments, opts) do
    Expense
    |> Ash.Query.for_read(:paid_without_bank_payment, Map.take(arguments, [:amount, :currency, :booked_on]))
    |> Ash.exists?(opts)
  end
end
