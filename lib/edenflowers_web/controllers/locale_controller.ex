defmodule EdenflowersWeb.LocaleController do
  use EdenflowersWeb, :controller

  def index(conn, %{"locale" => locale} = params) do
    if Edenflowers.Locales.supported?(locale) do
      conn
      |> put_session(Localize.Plug.PutLocale.session_key(), locale)
      |> redirect(to: get_redirect_path(conn, params))
    else
      redirect(conn, to: ~p"/")
    end
  end

  defp get_redirect_path(_conn, %{"redirect_to" => redirect_to}), do: URI.decode_www_form(redirect_to)

  defp get_redirect_path(conn, _params) do
    with [referer] <- get_req_header(conn, "referer"),
         %URI{path: path} when is_binary(path) <- URI.parse(referer) do
      path
    else
      _ -> ~p"/"
    end
  end
end
