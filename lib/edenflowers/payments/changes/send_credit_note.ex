defmodule Edenflowers.Payments.Changes.SendCreditNote do
  @moduledoc """
  Emails a credit note to the buyer of the Invoice it cancels, in that
  Invoice's language, with its PDF, as Jennie rewrote it if she did, then stamps
  `sent_at`. The PDF is made first, so a render failure sends nothing.
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
      credit_note = Ash.load!(changeset.data, :invoice, authorize?: false)
      edits = Edits.from_changeset(changeset)

      with {:ok, pdf} <- InvoicePdf.for_email(credit_note),
           {:ok, _result} <-
             credit_note
             |> Email.credit_note()
             |> Edits.apply_to(edits)
             |> Swoosh.Email.attachment(InvoicePdf.attachment(pdf, credit_note))
             |> Mailer.deliver() do
        Logger.info("Sent credit note #{credit_note.number} (#{credit_note.id})")

        changeset
        |> Ash.Changeset.force_change_attribute(:sent_at, DateTime.utc_now())
        |> Ash.Changeset.set_context(%{paper_trail_metadata: Edits.for_log(edits)})
      else
        {:error, error} -> Ash.Changeset.add_error(changeset, "Failed to send credit note: #{inspect(error)}")
      end
    end)
  end
end
