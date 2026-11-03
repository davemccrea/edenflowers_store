defmodule Edenflowers.Orders.Order.Validations.NotInvoiced do
  @moduledoc """
  Refuses cancelling an order while an issued invoice covers it
  (`invoiced?`, read fresh). Jennie credits the invoice first, which
  unlocks the order. Edits are narrower: `Changes.KeepInvoicedAmounts`.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "admin"]

  @impl true
  def validate(changeset, _opts, _context) do
    if Ash.load!(changeset.data, :invoiced?, authorize?: false, reuse_values?: false).invoiced?,
      do: {:error, message: ~t"Credit the invoice first"},
      else: :ok
  end
end
