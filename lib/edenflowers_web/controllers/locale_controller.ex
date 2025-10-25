defmodule EdenflowersWeb.LocaleController do
  use EdenflowersWeb, :controller

  def index(conn, %{"cldr_locale" => cldr_locale} = params) do
    redirect_path = get_redirect_path(conn, params)

    conn
    |> put_session("cldr_locale", cldr_locale)
    |> redirect(to: redirect_path)
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
