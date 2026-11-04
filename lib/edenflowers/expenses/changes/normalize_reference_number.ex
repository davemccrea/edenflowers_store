defmodule Edenflowers.Expenses.Changes.NormalizeReferenceNumber do
  @moduledoc """
  Stores an expense's reference number the way the bank sync compares it, so
  `1 23453` from the invoice matches `00000000000000123453` from the bank.
  """
  use Ash.Resource.Change

  alias Edenflowers.Payments.ReferenceNumber

  @impl true
  def change(changeset, _opts, _context) do
    if Ash.Changeset.changing_attribute?(changeset, :reference_number) do
      reference = Ash.Changeset.get_attribute(changeset, :reference_number)
      Ash.Changeset.force_change_attribute(changeset, :reference_number, ReferenceNumber.normalize(reference))
    else
      changeset
    end
  end
end
