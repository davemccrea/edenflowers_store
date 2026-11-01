defmodule EdenflowersWeb.Admin.InvoiceController do
  @moduledoc """
  Opens an invoice's or a credit note's PDF for Jennie, named in its
  language (`lasku-1001.pdf`, `hyvityslasku-1002.pdf`), as the customer gets
  it.
  """

  use EdenflowersWeb, :controller

  require Logger

  alias Edenflowers.Payments
  alias Edenflowers.Payments.InvoicePdf

  def show(%{assigns: %{current_user: %{admin: true} = admin}} = conn, %{"id" => id}) do
    send_pdf(conn, id, Payments.get_invoice(id, actor: admin))
  end

  def show(conn, _params), do: send_resp(conn, :not_found, "Not found")

  def credit_note(%{assigns: %{current_user: %{admin: true} = admin}} = conn, %{"id" => id}) do
    send_pdf(conn, id, Payments.get_credit_note(id, actor: admin, load: :invoice))
  end

  def credit_note(conn, _params), do: send_resp(conn, :not_found, "Not found")

  defp send_pdf(conn, id, document) do
    with {:ok, document} <- document,
         {:ok, pdf} <- InvoicePdf.generate(document) do
      send_download(conn, {:binary, pdf},
        filename: InvoicePdf.filename(document),
        content_type: "application/pdf",
        disposition: :inline
      )
    else
      error ->
        Logger.error("PDF #{id} not rendered: #{inspect(error)}")
        send_resp(conn, :not_found, "Not found")
    end
  end
end
