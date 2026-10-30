defmodule Edenflowers.Expenses.Actions.ImportInvoiceEmails do
  @moduledoc """
  Imports the invoice emails filed in the Fastmail folder `Fakturor`.

  Each PDF attachment is uploaded to Papra, whose `document:created` webhook
  records it for extraction like any other document. The email then moves to `Fakturor/Importerade`, which is what stops it being
  imported again. Emails without a PDF stay in `Fakturor` for Jennie.

  Does nothing without a Fastmail API token, which only production has: dev
  and worktrees use production Papra and must never touch the mailbox.
  """
  use Ash.Resource.Actions.Implementation

  require Logger

  alias Edenflowers.External.FastmailAPI
  alias Edenflowers.External.PapraAPI

  @inbox ["Fakturor"]
  @imported ["Fakturor", "Importerade"]

  @impl true
  def run(_input, _opts, _context) do
    if FastmailAPI.configured?(), do: import_emails(), else: :ok
  end

  # One email failing doesn't hold up the rest; its error fails the job and alerts.
  defp import_emails do
    with {:ok, conn} <- FastmailAPI.connect(),
         {:ok, inbox_id} <- FastmailAPI.mailbox_id(conn, @inbox),
         {:ok, imported_id} <- FastmailAPI.mailbox_id(conn, @imported),
         {:ok, emails} <- FastmailAPI.list_emails(conn, inbox_id) do
      emails
      |> Enum.map(&%{&1 | attachments: Enum.filter(&1.attachments, fn attachment -> pdf?(attachment) end)})
      |> Enum.reject(&(&1.attachments == []))
      |> Enum.map(&import_email(conn, &1, inbox_id, imported_id))
      |> Enum.find(:ok, &(&1 != :ok))
    end
  end

  defp import_email(conn, email, inbox_id, imported_id) do
    with :ok <- import_pdfs(conn, email.attachments) do
      FastmailAPI.move_email(conn, email.id, inbox_id, imported_id)
    end
  end

  # Some senders label PDFs `application/octet-stream`.
  defp pdf?(attachment) do
    attachment.type == "application/pdf" or String.ends_with?(String.downcase(attachment.name), ".pdf")
  end

  defp import_pdfs(conn, pdfs) do
    Enum.reduce_while(pdfs, :ok, fn pdf, :ok ->
      case import_pdf(conn, pdf) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp import_pdf(conn, pdf) do
    with {:ok, body} <- FastmailAPI.download(conn, pdf) do
      case PapraAPI.impl().upload_document(pdf.name, body) do
        :ok ->
          :ok

        # ponytail: Papra's hash dedupe is the only record of an upload, and its rejection doesn't say which
        # document holds the PDF. Usually the email was imported before and couldn't be moved, but if
        # Papra's webhook never arrived, the document has no expense. Logged as an error so it alerts.
        {:error, :already_exists} ->
          Logger.error(
            "Invoice PDF #{pdf.name} is already in Papra, so it was not imported again. " <>
              "If admin has no expense for it, delete the document in Papra and upload the PDF again."
          )

          :ok

        {:error, error} ->
          {:error, error}
      end
    end
  end
end
