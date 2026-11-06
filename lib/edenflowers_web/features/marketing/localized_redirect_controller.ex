defmodule EdenflowersWeb.Marketing.LocalizedRedirectController do
  @moduledoc """
  Sends URLs without a language, like bare / or a shared /product/:slug, to the
  page in the visitor's language: their session's, else Accept-Language's, else
  Swedish, as resolved by `Localize.Plug.PutLocale`. A browser language the shop
  doesn't speak, like German, gets English, its nearest CLDR match. The query
  string comes along, so tracking tags on a shared link survive.
  """
  use EdenflowersWeb, :controller

  def show(conn, _params), do: localized_redirect(conn, ~q"/#{language}")
  def product(conn, %{"slug" => slug}), do: localized_redirect(conn, ~q"/#{language}/product/#{slug}")
  def courses(conn, _params), do: localized_redirect(conn, ~q"/#{language}/courses")
  def course(conn, %{"slug" => slug}), do: localized_redirect(conn, ~q"/#{language}/courses/#{slug}")
  def weddings(conn, _params), do: localized_redirect(conn, ~q"/#{language}/weddings")
  def gift_voucher(conn, _params), do: localized_redirect(conn, ~q"/#{language}/gift-voucher")
  def pass_it_on(conn, _params), do: localized_redirect(conn, ~q"/#{language}/pass-it-on")

  defp localized_redirect(conn, path) do
    path = if conn.query_string == "", do: path, else: path <> "?" <> conn.query_string

    conn
    |> put_resp_header("vary", "accept-language, cookie")
    |> redirect(to: path)
  end
end
