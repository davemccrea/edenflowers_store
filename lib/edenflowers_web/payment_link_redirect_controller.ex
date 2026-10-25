defmodule EdenflowersWeb.PaymentLinkRedirectController do
  use EdenflowersWeb, :controller

  def order(conn, %{"token" => token}), do: redirect_to(conn, ~p"/pay/orders/#{token}")
  def course(conn, %{"token" => token}), do: redirect_to(conn, ~p"/pay/courses/#{token}")

  defp redirect_to(conn, path) do
    path = if conn.query_string == "", do: path, else: path <> "?" <> conn.query_string
    redirect(conn, to: path)
  end
end
