defmodule Edenflowers.Expenses.Changes.ForgetBankPayment do
  @moduledoc """
  Jennie says the bank payment linked to an expense didn't pay it. The expense
  lets go of the payment's id, so the payment goes back to missing a receipt
  and the real one can link, and keeps it among its unlinked ids, so that
  payment never links to it or settles another expense by itself again.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    unlinked = changeset.data.unlinked_bank_transaction_ids ++ List.wrap(changeset.data.bank_transaction_id)

    changeset
    |> Ash.Changeset.force_change_attribute(:unlinked_bank_transaction_ids, unlinked)
    |> Ash.Changeset.force_change_attribute(:bank_transaction_id, nil)
    |> Ash.Changeset.force_change_attribute(:matched_by_amount, false)
  end
end
