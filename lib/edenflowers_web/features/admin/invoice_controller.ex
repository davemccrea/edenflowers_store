defmodule EdenflowersWeb.Admin.InvoiceController do
  @moduledoc """
  Opens an invoice's PDF for Jennie, named in the invoice's language
  (`lasku-1001.pdf`), as the customer gets it.
  """

  use EdenflowersWeb, :controller

  require Logger

  alias Edenflowers.Payments
  alias Edenflowers.Payments.InvoicePdf

  def show(%{assigns: %{current_user: %{admin: true} = admin}} = conn, %{"id" => id}) do
    with {:ok, invoice} <- Payments.get_invoice(id, actor: admin),
         {:ok, pdf} <- InvoicePdf.generate(invoice) do
      send_download(conn, {:binary, pdf},
        filename: InvoicePdf.filename(invoice),
        content_type: "application/pdf",
        disposition: :inline
      )
    else
      error ->
        Logger.error("Invoice PDF #{id} not rendered: #{inspect(error)}")
        send_resp(conn, :not_found, "Not found")
    end
  end

  def show(conn, _params), do: send_resp(conn, :not_found, "Not found")
end
