defmodule EdenflowersWeb.Admin.ReportController do
  @moduledoc """
  Builds and downloads an authenticated monthly accounting report ZIP.
  """

  use EdenflowersWeb, :controller

  require Logger

  alias Edenflowers.Accounting.MonthlyReport

  def show(%{assigns: %{current_user: %{admin: true}}} = conn, %{"month" => month}) do
    with {:ok, year, month_number} <- parse_month(month),
         {:ok, filename, zip} <- MonthlyReport.build(year, month_number) do
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
