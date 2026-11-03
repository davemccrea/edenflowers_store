defmodule Edenflowers.Payments.Changes.FreezeInvoiceContent do
  @moduledoc """
  Freezes the issued standalone invoice's formatted PDF content after its
  numeric snapshot and number are assigned, then renders and stores its PDF,
  so a render failure issues nothing.
  """
  use Ash.Resource.Change

  alias Edenflowers.Payments.InvoicePdf

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      with {:ok, invoice} <- Ash.Changeset.apply_attributes(changeset),
           {:ok, content} <- InvoicePdf.content(invoice),
           {:ok, pdf} <- InvoicePdf.render(%{invoice | content: content}) do
        Ash.Changeset.force_change_attributes(changeset, %{content: content, pdf: pdf})
      else
        {:error, error} -> Ash.Changeset.add_error(changeset, error)
      end
    end)
  end
end
