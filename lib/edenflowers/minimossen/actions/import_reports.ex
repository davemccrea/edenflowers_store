defmodule Edenflowers.Minimossen.Actions.ImportReports do
  @moduledoc """
  Imports the Winpos reports filed in the Fastmail folder `Winpos`.

  Reads every `.XLS` attachment of an email before recording any, so a report that
  can't be read records nothing from its email, fails the run, which alerts, and
  leaves the email in `Winpos`. Recorded emails move to `Winpos/Importerade`,
  which is what stops them being imported again. Emails without a report stay put.

  Does nothing without a Fastmail API token, which only production has: dev and
  worktrees must never touch the mailbox.
  """
  use Ash.Resource.Actions.Implementation

  alias Edenflowers.External.FastmailAPI
  alias Edenflowers.Minimossen
  alias Edenflowers.Minimossen.WinposReport

  @inbox ["Winpos"]
  @imported ["Winpos", "Importerade"]

  @impl true
  def run(_input, _opts, context) do
    if FastmailAPI.configured?(), do: import_emails(Ash.Context.to_opts(context)), else: :ok
  end

  # One email failing doesn't hold up the rest; its error fails the job and alerts.
  defp import_emails(opts) do
    with {:ok, conn} <- FastmailAPI.connect(),
         {:ok, inbox_id} <- FastmailAPI.mailbox_id(conn, @inbox),
         {:ok, imported_id} <- FastmailAPI.mailbox_id(conn, @imported),
         {:ok, emails} <- FastmailAPI.list_emails(conn, inbox_id) do
      emails
      |> Enum.map(&%{&1 | attachments: Enum.filter(&1.attachments, fn attachment -> xls?(attachment) end)})
      |> Enum.reject(&(&1.attachments == []))
      |> Enum.map(&import_email(conn, &1, inbox_id, imported_id, opts))
      |> Enum.find(:ok, &(&1 != :ok))
    end
  end

  defp import_email(conn, email, inbox_id, imported_id, opts) do
    with {:ok, reports} <- read_reports(conn, email.attachments),
         :ok <- record(reports, opts) do
      FastmailAPI.move_email(conn, email.id, inbox_id, imported_id)
    end
  end

  defp xls?(attachment) do
    attachment.type == "application/vnd.ms-excel" or String.ends_with?(String.downcase(attachment.name), ".xls")
  end

  defp read_reports(conn, attachments) do
    Enum.reduce_while(attachments, {:ok, []}, fn attachment, {:ok, reports} ->
      with {:ok, body} <- FastmailAPI.download(conn, attachment),
           {:ok, report} <- WinposReport.parse(body) do
        {:cont, {:ok, [report | reports]}}
      else
        {:error, error} -> {:halt, {:error, {attachment.name, error}}}
      end
    end)
  end

  defp record(reports, opts) do
    Enum.reduce_while(for(report <- reports, group <- report.groups, do: {report.week_start, group}), :ok, fn
      {week_start, group}, :ok ->
        attrs = %{week_start: week_start, group_code: group.code, group_name: group.name, gross: group.gross}

        case Minimossen.record_minimossen_sales(attrs, opts) do
          {:ok, _sales} -> {:cont, :ok}
          {:error, error} -> {:halt, {:error, error}}
        end
    end)
  end
end
