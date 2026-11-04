defmodule Edenflowers.Bank.Actions.BookedTransactions do
  @moduledoc """
  Reads the booked transactions between two dates on every account of the
  current bank connection, oldest first. Returns nil without Enable Banking
  configured (only production is), and an error before the bank is first
  connected or once the consent has ended.
  """
  use Ash.Resource.Actions.Implementation

  import Edenflowers.Actors

  alias Edenflowers.Bank
  alias Edenflowers.External.EnableBankingAPI

  @impl true
  def run(input, _opts, _context) do
    if EnableBankingAPI.configured?() do
      case Bank.current_bank_connection(actor: system_actor(), load: [:expired]) do
        {:ok, %{expired: false} = connection} -> read(connection, input.arguments)
        {:ok, _none_or_expired} -> {:error, :bank_not_connected}
        error -> error
      end
    else
      {:ok, nil}
    end
  end

  defp read(connection, arguments) do
    read_all =
      Enum.reduce_while(connection.account_ids, {:ok, []}, fn account_id, {:ok, acc} ->
        options = [date_to: arguments.date_to, psu_headers: Map.to_list(arguments[:psu_headers] || %{})]

        case EnableBankingAPI.booked_transactions(account_id, arguments.date_from, options) do
          {:ok, transactions} -> {:cont, {:ok, acc ++ transactions}}
          error -> {:halt, error}
        end
      end)

    with {:ok, transactions} <- read_all do
      {:ok, Enum.sort_by(transactions, & &1.booked_on, Date)}
    end
  end
end
