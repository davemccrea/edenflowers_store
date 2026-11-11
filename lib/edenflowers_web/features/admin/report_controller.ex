defmodule EdenflowersWeb.Admin.ReportController do
  @moduledoc """
  Builds and downloads an authenticated monthly accounting report ZIP.
  """

  use EdenflowersWeb, {:controller, gettext_domain: "admin"}

  require Logger

  alias Edenflowers.Accounting.MonthlyReport
  alias Edenflowers.Events

  def show(%{assigns: %{current_user: %{admin: true} = user}} = conn, %{"month" => month}) do
    with {:ok, year, month_number} <- parse_month(month),
         {:ok, filename, zip, missing} <- MonthlyReport.build(year, month_number, psu_headers: psu_headers(conn)) do
      if :bank_statement in missing do
        Events.broadcast(Events.admin_report(user.id), {:bank_statement_missing, month})
      end

      send_download(conn, {:binary, zip}, filename: filename, content_type: "application/zip")
    else
      error ->
        Logger.error("Monthly report for #{inspect(month)} failed: #{inspect(error)}")

        conn
        |> put_flash(:error, ~t"The report couldn't be built. Please try again.")
        |> redirect(to: ~p"/admin")
    end
  end

  def show(conn, _params), do: send_resp(conn, :not_found, "Not found")

  # Forward the available browser headers as payment service user (PSU) headers
  # for the bank request. Use Cloudflare's visitor IP rather than the tunnel's
  # address, which is what conn.remote_ip contains behind Cloudflare.
  defp psu_headers(conn) do
    ip_address = List.first(get_req_header(conn, "cf-connecting-ip")) || to_string(:inet.ntoa(conn.remote_ip))

    forwarded =
      for header <- ~w(user-agent referer accept accept-charset accept-encoding accept-language),
          value = List.first(get_req_header(conn, header)),
          into: %{},
          do: {"psu-" <> header, value}

    Map.put(forwarded, "psu-ip-address", ip_address)
  end

  defp parse_month(<<year::binary-4, "-", month::binary-2>>) do
    with {year, ""} <- Integer.parse(year),
         {month, ""} when month in 1..12 <- Integer.parse(month) do
      {:ok, year, month}
    else
      _ -> :error
    end
  end

  defp parse_month(_), do: :error
end
