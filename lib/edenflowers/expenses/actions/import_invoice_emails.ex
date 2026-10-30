defmodule Edenflowers.Expenses.Actions.ImportInvoiceEmails do
  @moduledoc """
  Imports the invoice emails filed in the Fastmail folder `Fakturor`.

  Each PDF attachment is uploaded to Papra and recorded as an `ExpenseImport`.
  The email then moves to `Fakturor/Importerade`, which is what stops it being
  imported again. Emails without a PDF stay in `Fakturor` for Jennie.

  Does nothing without a Fastmail API token, which only production has: dev
  and worktrees use production Papra and must never touch the mailbox.
  """
  use Ash.Resource.Actions.Implementation

  require Logger

  alias Edenflowers.Expenses
  alias Edenflowers.External.FastmailAPI
  alias Edenflowers.External.PapraAPI

  @inbox ["Fakturor"]
  @imported ["Fakturor", "Importerade"]

  @impl true
  def run(_input, _opts, context) do
    if FastmailAPI.configured?(), do: import_emails(context), else: :ok
  end

  # One email failing doesn't hold up the rest; its error fails the job and alerts.
  defp import_emails(context) do
    with {:ok, conn} <- FastmailAPI.connect(),
         {:ok, inbox_id} <- FastmailAPI.mailbox_id(conn, @inbox),
         {:ok, imported_id} <- FastmailAPI.mailbox_id(conn, @imported),
         {:ok, emails} <- FastmailAPI.list_emails(conn, inbox_id) do
      emails
      |> Enum.map(&%{&1 | attachments: Enum.filter(&1.attachments, fn attachment -> pdf?(attachment) end)})
      |> Enum.reject(&(&1.attachments == []))
      |> Enum.map(&import_email(conn, &1, inbox_id, imported_id, context))
      |> Enum.find(:ok, &(&1 != :ok))
    end
  end

  defp import_email(conn, email, inbox_id, imported_id, context) do
    with :ok <- import_pdfs(conn, email.attachments, context) do
      FastmailAPI.move_email(conn, email.id, inbox_id, imported_id)
    end
  end

  # Some senders label PDFs `application/octet-stream`.
  defp pdf?(attachment) do
    attachment.type == "application/pdf" or String.ends_with?(String.downcase(attachment.name), ".pdf")
  end

  defp import_pdfs(conn, pdfs, context) do
    Enum.reduce_while(pdfs, :ok, fn pdf, :ok ->
      case import_pdf(conn, pdf, context) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp import_pdf(conn, pdf, context) do
    with {:ok, body} <- FastmailAPI.download(conn, pdf) do
      case PapraAPI.impl().upload_document(pdf.name, body) do
        {:ok, document} ->
          record(document, context)

        # ponytail: Papra's hash dedupe is the only record of an upload, and its rejection doesn't say which
        # document holds the PDF. Usually the email was imported before and couldn't be moved, but if the
        # import failed to save after the upload, the document has no expense. Logged as an error so it
        # alerts. Record uploads per attachment if this ever happens.
        {:error, :already_exists} ->
          Logger.error(
            "Invoice PDF #{pdf.name} is already in Papra, so it was not imported again. " <>
              "If admin has no expense for it, tag it receipt in Papra."
          )

          :ok

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp record(document, context) do
    case Expenses.record_expense_import(document, Ash.Context.to_opts(context)) do
      {:ok, _import} -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
