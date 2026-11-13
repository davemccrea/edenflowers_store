defmodule Edenflowers.Bank.Actions.SyncPayments do
  @moduledoc """
  Reads the booked transactions of every account on the current bank
  connection and settles what they pay: a payment out marks its expense paid,
  a transfer in is recorded on its invoice. Payments the matching can't place
  are left for Jennie. Every payment out is kept, and linked to its receipt
  when one paid by other means matches, so Jennie sees which have none. Then
  stores the accounts' balance for the Overview.

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
      result = with :ok <- sync(connection), do: Bank.match_bank_receipts(actor: system_actor())
      store_balance(connection)
      result
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

  # A balance the bank won't give is logged and skipped: the Overview shows
  # how old its figure is, and settling payments matters more.
  # shortcut: several accounts are added up into one balance, show one each once the shop has two.
  defp store_balance(connection) do
    read_all =
      Enum.reduce_while(connection.account_ids, {:ok, []}, fn account_id, {:ok, acc} ->
        case EnableBankingAPI.balances(account_id) do
          {:ok, balances} -> {:cont, {:ok, [balances | acc]}}
          error -> {:halt, error}
        end
      end)

    with {:ok, balances} <- read_all,
         {:ok, _connection} <-
           Bank.record_bank_balance(
             connection,
             %{available_balance: sum(balances, :available), booked_balance: sum(balances, :booked)},
             actor: system_actor()
           ) do
      :ok
    else
      error -> Logger.warning("Reading the bank balance failed: #{inspect(error)}")
    end
  end

  defp sum(balances, kind) do
    case Enum.reject(Enum.map(balances, & &1[kind]), &is_nil/1) do
      [] -> nil
      amounts -> Enum.reduce(amounts, &Decimal.add/2)
    end
  end

  # Oldest first, so of two payments of one amount the earlier settles the earlier expense.
  defp settle_all(transactions) do
    transactions
    |> Enum.sort_by(& &1.booked_on, Date)
    |> Enum.reduce_while(:ok, fn transaction, :ok ->
      case settle(transaction) do
        {:error, error} -> {:halt, {:error, error}}
        _settled_or_not -> {:cont, :ok}
      end
    end)
  end

  defp settle(%{direction: :out} = transaction) do
    with :ok <- record(transaction), true <- Expense.Currency.match?(transaction.currency) do
      Expenses.settle_expense_from_bank(
        transaction.reference_number,
        transaction.amount,
        transaction.currency,
        transaction.booked_on,
        %{bank_transaction_id: transaction.id},
        actor: system_actor()
      )
    end
  end

  defp settle(%{direction: :in, reference_number: reference, id: id, currency: "eur"} = transaction)
       when is_binary(reference) and is_binary(id) do
    Payments.settle_invoice_from_bank(reference, transaction.amount, transaction.booked_on, id, actor: system_actor())
  end

  defp settle(_transaction), do: :skip

  # Without the bank's id a payment read again couldn't be told from a new one.
  defp record(%{id: nil}), do: :ok

  defp record(transaction) do
    attrs = %{
      bank_id: transaction.id,
      booked_on: transaction.booked_on,
      amount: transaction.amount,
      currency: transaction.currency,
      counterparty: transaction.counterparty,
      message: transaction.message,
      reference_number: transaction.reference_number
    }

    with {:ok, _transaction} <- Bank.record_bank_transaction(attrs, actor: system_actor()), do: :ok
  end
end
