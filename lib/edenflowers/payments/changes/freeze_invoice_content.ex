defmodule Edenflowers.Payments.Changes.FreezeInvoiceContent do
  @moduledoc "Freezes the issued standalone invoice's formatted PDF content after its numeric snapshot and number are assigned."
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
