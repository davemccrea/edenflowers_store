defmodule Edenflowers.Payments.Changes.FreezeInvoiceContent do
  @moduledoc """
  Freezes what a new invoice's PDF prints onto its `content`
  (`InvoicePdf.content/1`): the purchase's lines, totals and VAT, the earlier
  invoices and money paid before it, the seller's and buyer's details, the
  amount due and how to pay it.

  It runs in the insert's transaction once the number is taken, as the PDF
  prints the number and builds the viitenumero and virtual barcode from it.
  From then on every render, the email and each resend print this content,
  however the purchase or the shop's details change.
  """
  use Ash.Resource.Change

  alias Edenflowers.Payments.InvoicePdf

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      with {:ok, invoice} <- Ash.Changeset.apply_attributes(changeset),
           {:ok, content} <- InvoicePdf.content(invoice) do
        Ash.Changeset.force_change_attribute(changeset, :content, content)
      else
        {:error, error} -> Ash.Changeset.add_error(changeset, error)
      end
    end)
  end
end
