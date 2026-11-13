defmodule Edenflowers.Expenses.Changes.MatchBankPayments do
  @moduledoc """
  Matches the stored bank payments still awaiting a receipt once an expense is
  saved, so a receipt arriving after its payment is matched at once instead of
  at the next bank sync, hours later. A failed match is only logged: the
  expense is still saved, and the next sync tries again.
  """
  use Ash.Resource.Change

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Bank

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn
      _changeset, {:ok, expense} ->
        with {:error, error} <- Bank.match_bank_receipts(actor: system_actor()) do
          Logger.warning("Matching bank payments to expense #{expense.id} failed: #{inspect(error)}")
        end

        {:ok, expense}

      _changeset, error ->
        error
    end)
  end
end
