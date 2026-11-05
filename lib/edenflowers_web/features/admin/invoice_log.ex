defmodule EdenflowersWeb.Admin.InvoiceLog do
  @moduledoc """
  The invoice page's history, newest first. Financial events come from the
  documents and ledger records; each successful email comes from PaperTrail.
  Draft edits are intentionally omitted, as on the other admin detail pages.
  """
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "admin"]

  alias EdenflowersWeb.Admin.OrderLog

  def entries(invoice, locale) do
    (lifecycle(invoice) ++
       invoice_emails(invoice) ++
       OrderLog.entries([], invoice.payments, locale) ++
       credit_note_entries(invoice.credit_note, invoice.buyer_email))
    |> Enum.sort_by(& &1.at, {:desc, DateTime})
  end

  defp lifecycle(invoice) do
    created = %{at: invoice.inserted_at, title: ~t"Draft created", details: []}
    issued = if invoice.issued_at, do: [%{at: invoice.issued_at, title: ~t"Invoice issued", details: []}], else: []
    issued ++ [created]
  end

  defp invoice_emails(invoice) do
    Enum.map(invoice.paper_trail_versions, fn version ->
      %{
        at: version.version_inserted_at,
        title: if(version.reminder, do: ~t"Payment reminder emailed", else: ~t"Invoice emailed"),
        details: email_details(version, invoice.buyer_email)
      }
    end)
  end

  defp credit_note_entries(nil, _email), do: []

  defp credit_note_entries(credit_note, email) do
    issued = %{
      at: credit_note.inserted_at,
      title: ~t"Credit note #{number = credit_note.number} issued",
      details: if(credit_note.reason, do: [{~t"Reason", credit_note.reason}], else: [])
    }

    emails =
      Enum.map(credit_note.paper_trail_versions, fn version ->
        %{
          at: version.version_inserted_at,
          title: ~t"Credit note emailed",
          details: email_details(version, email)
        }
      end)

    emails ++ [issued]
  end

  defp email_details(version, email) do
    [{~t"Sent to", email}] ++ EdenflowersWeb.Admin.OrderLog.message_details(version)
  end
end
