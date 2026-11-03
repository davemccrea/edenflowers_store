defmodule Edenflowers.Payments.Changes.IssueCreditNote do
  @moduledoc """
  Dates a new credit note today in Helsinki and gives it the next number in
  the series it shares with Invoices (`NumberSeries`), taken just before the
  insert, then renders and stores its PDF, so a render failure makes no
  credit note.
  """
  use Ash.Resource.Change

  alias Edenflowers.Payments.Invoice
  alias Edenflowers.Payments.InvoicePdf
  alias Edenflowers.Payments.NumberSeries
  alias Edenflowers.ShopTime

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.force_change_attribute(:credit_date, ShopTime.today())
    |> Ash.Changeset.before_action(fn changeset ->
      changeset = Ash.Changeset.force_change_attribute(changeset, :number, NumberSeries.take())

      with {:ok, note} <- Ash.Changeset.apply_attributes(changeset),
           {:ok, invoice} <- Ash.get(Invoice, note.invoice_id, authorize?: false),
           {:ok, pdf} <- InvoicePdf.render(%{note | invoice: invoice}) do
        Ash.Changeset.force_change_attribute(changeset, :pdf, pdf)
      else
        {:error, error} -> Ash.Changeset.add_error(changeset, error)
      end
    end)
  end
end
