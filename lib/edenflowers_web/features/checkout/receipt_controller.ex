defmodule EdenflowersWeb.Checkout.ReceiptController do
  use EdenflowersWeb, :controller

  alias Edenflowers.Orders.Receipt
  alias EdenflowersWeb.Checkout.OrderLive

  def show(conn, %{"id" => id}) do
    with {:ok, %{state: :placed} = order} <-
           OrderLive.get_order(id, get_session(conn, :guest_order_id), conn.assigns[:current_user]),
         {:ok, order} <- Receipt.load_for_receipt(order),
         {:ok, pdf} <- Receipt.generate(order) do
      send_download(conn, {:binary, pdf},
        filename: "eden-flowers-#{order.order_reference}.pdf",
        content_type: "application/pdf"
      )
    else
      _ -> send_resp(conn, :not_found, "Not found")
    end
  end
end
