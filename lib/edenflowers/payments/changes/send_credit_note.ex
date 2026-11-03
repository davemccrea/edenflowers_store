defmodule Edenflowers.Payments.Changes.SendCreditNote do
  @moduledoc """
  Emails a credit note to the buyer of the Invoice it cancels, in that
  Invoice's language, with its PDF and Jennie's message, then stamps
  `sent_at`. The PDF is made first, so a render failure sends nothing.
  """
  use Ash.Resource.Change

  require Logger

  alias Edenflowers.Email
  alias Edenflowers.Mailer
  alias Edenflowers.Payments.InvoicePdf

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      credit_note = Ash.load!(changeset.data, :invoice, authorize?: false)
      message = Ash.Changeset.get_argument(changeset, :message)

      with {:ok, pdf} <- InvoicePdf.generate(credit_note),
           {:ok, _result} <-
             credit_note
             |> Email.credit_note(message)
             |> Swoosh.Email.attachment(InvoicePdf.attachment(pdf, credit_note))
             |> Mailer.deliver() do
        Logger.info("Sent credit note #{credit_note.number} (#{credit_note.id})")

        changeset
        |> Ash.Changeset.force_change_attribute(:sent_at, DateTime.utc_now())
        |> Ash.Changeset.set_context(%{paper_trail_metadata: %{email_message: message}})
      else
        {:error, error} -> Ash.Changeset.add_error(changeset, "Failed to send credit note: #{inspect(error)}")
      end
    end)
  end
end
