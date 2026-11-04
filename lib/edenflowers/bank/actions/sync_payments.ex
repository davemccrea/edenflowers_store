defmodule Edenflowers.Bank.Actions.SyncPayments do
  @moduledoc """
  Reads the booked transactions of every account on the current bank
  connection and settles what they pay: a payment out marks its expense paid,
  a transfer in is recorded on its invoice. Payments the matching can't place
  are left for Jennie.

  Does nothing without Enable Banking configured (only production is), before
  the bank is first connected, or once the consent has ended.
  """
  use Ash.Resource.Actions.Implementation

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Bank
  alias Edenflowers.Expenses
  alias Edenflowers.Expenses.Expense
  alias Edenflowers.External.EnableBankingAPI
  alias Edenflowers.Payments

  # ponytail: re-reads two weeks each run instead of tracking a cursor; matching
  # is idempotent, since a settled expense no longer awaits a payment.
  @lookback_days 14

  @impl true
  def run(_input, _opts, _context) do
    with true <- EnableBankingAPI.configured?(),
         {:ok, %{expired: false} = connection} <-
           Bank.current_bank_connection(actor: system_actor(), load: [:expired]) do
      sync(connection)
    else
      _nothing_to_read -> :ok
    end
  end

  defp sync(connection) do
    date_from = Enum.max([DateTime.to_date(connection.inserted_at), Date.add(Date.utc_today(), -@lookback_days)], Date)

    Enum.reduce_while(connection.account_ids, :ok, fn account_id, :ok ->
      with {:ok, transactions} <- EnableBankingAPI.booked_transactions(account_id, date_from),
           :ok <- settle_all(transactions) do
        {:cont, :ok}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp settle_all(transactions) do
    Enum.reduce_while(transactions, :ok, fn transaction, :ok ->
      case settle(transaction) do
        {:error, error} -> {:halt, {:error, error}}
        _settled_or_not -> {:cont, :ok}
      end
    end)
  end

  defp settle(%{direction: :out, reference_number: reference} = transaction) when is_binary(reference) do
    if Expense.Currency.match?(transaction.currency) do
      Expenses.settle_expense_from_bank(
        reference,
        transaction.amount,
        transaction.currency,
        transaction.booked_on,
        actor: system_actor()
      )
    end
  end

  defp settle(%{direction: :in, reference_number: reference, id: id, currency: "eur"} = transaction)
       when is_binary(reference) and is_binary(id) do
    Payments.settle_invoice_from_bank(reference, transaction.amount, transaction.booked_on, id, actor: system_actor())
  end

  defp settle(_transaction), do: :skip
end
