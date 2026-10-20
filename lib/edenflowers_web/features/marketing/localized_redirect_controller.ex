defmodule EdenflowersWeb.Marketing.LocalizedRedirectController do
  @moduledoc """
  Sends bare / to the home page in the visitor's language: their session's,
  else Accept-Language's, else Swedish, as resolved by `Localize.Plug.PutLocale`.
  """
  use EdenflowersWeb, :controller

  def show(conn, _params) do
    conn
    |> put_resp_header("vary", "accept-language, cookie")
    |> redirect(to: ~q"/#{language}")
  end
end
