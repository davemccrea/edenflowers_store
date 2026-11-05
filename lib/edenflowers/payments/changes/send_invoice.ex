defmodule Edenflowers.Payments.Changes.SendInvoice do
  @moduledoc """
  Emails an invoice to its buyer in the invoice's own language, with its PDF,
  as Jennie rewrote it if she did, then stamps `sent_at`. The PDF is made first, so a
  render failure sends nothing. Whether it is `overdue?` is read as it is
  sent: overdue, the email is a reminder, and the send's version says so.
  """
  use Ash.Resource.Change

  require Logger

  alias Edenflowers.Email
  alias Edenflowers.Email.Edits
  alias Edenflowers.Mailer
  alias Edenflowers.Payments.InvoicePdf

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      invoice = changeset.data
      edits = Edits.from_changeset(changeset)

      loaded = load_for_email(invoice)

      with {:ok, pdf} <- InvoicePdf.for_email(invoice),
           {:ok, _result} <-
             loaded
             |> Email.invoice()
             |> Edits.apply_to(edits)
             |> Swoosh.Email.attachment(InvoicePdf.attachment(pdf, invoice))
             |> Mailer.deliver() do
        Logger.info("Sent invoice #{invoice.number} (#{invoice.id})")

        changeset
        |> Ash.Changeset.force_change_attribute(:sent_at, DateTime.utc_now())
        |> Ash.Changeset.set_context(%{
          paper_trail_metadata: Map.put(Edits.for_log(edits), :reminder, loaded.overdue?)
        })
      else
        {:error, error} -> Ash.Changeset.add_error(changeset, "Failed to send invoice: #{inspect(error)}")
      end
    end)
  end

  @doc "Loads only the standalone invoice balances used in its email and reminder."
  def load_for_email(invoice) do
    Ash.load!(invoice, [:overdue?, :amount_paid, :amount_unpaid], authorize?: false, reuse_values?: false)
  end
end
