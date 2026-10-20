defmodule EdenflowersWeb.Marketing.LocalizedRedirectController do
  @moduledoc """
  Sends bare / and the old unprefixed public URLs to the page in the visitor's
  language: their session's, else Accept-Language's, else Swedish, as resolved
  by `Localize.Plug.PutLocale`.
  """
  use EdenflowersWeb, :controller

  alias EdenflowersWeb.LocalizedPaths

  def show(conn, _params) do
    # The old URLs are the English paths without their /en prefix.
    english_path = "/en" <> String.trim_trailing(conn.request_path, "/")
    locale = Localize.get_locale().cldr_locale_id

    # Only a store category that no longer exists has no translation.
    path = LocalizedPaths.translate(english_path, locale) || LocalizedPaths.translate("/en/store", locale)

    conn
    |> put_resp_header("vary", "accept-language, cookie")
    |> redirect(to: path)
  end
end
