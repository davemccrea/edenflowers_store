defmodule EdenflowersWeb.Marketing.LocalizedRedirectController do
  @moduledoc """
  Sends URLs without a language, like bare / or a shared /product/:id, to the
  page in the visitor's language: their session's, else Accept-Language's, else
  Swedish, as resolved by `Localize.Plug.PutLocale`. The query string comes along,
  so tracking tags on a shared link survive.
  """
  use EdenflowersWeb, :controller

  def show(conn, _params), do: localized_redirect(conn, ~q"/#{language}")
  def product(conn, %{"id" => id}), do: localized_redirect(conn, ~q"/#{language}/product/#{id}")
  def courses(conn, _params), do: localized_redirect(conn, ~q"/#{language}/courses")
  def course(conn, %{"id" => id}), do: localized_redirect(conn, ~q"/#{language}/courses/#{id}")
  def weddings(conn, _params), do: localized_redirect(conn, ~q"/#{language}/weddings")

  defp localized_redirect(conn, path) do
    path = if conn.query_string == "", do: path, else: path <> "?" <> conn.query_string

    conn
    |> put_resp_header("vary", "accept-language, cookie")
    |> redirect(to: path)
  end
end
