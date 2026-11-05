defmodule Edenflowers.Payments.Changes.EditInvoiceDraft do
  @moduledoc false
  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      invoice = Edenflowers.Payments.Invoice.get_locked(changeset.data.id, [])

      if invoice && is_nil(invoice.issued_at),
        do: changeset,
        else: Ash.Changeset.add_error(changeset, "Issued invoices cannot be changed")
    end)
  end
end
