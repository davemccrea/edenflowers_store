defmodule EdenflowersWeb.LocaleController do
  @moduledoc """
  Stores a visitor's language choice and returns them to the requested page.
  """

  use EdenflowersWeb, :controller

  def index(conn, %{"locale" => locale} = params) do
    if Edenflowers.Locales.supported?(locale) do
      conn
      |> put_session(Localize.Plug.PutLocale.session_key(), locale)
      |> redirect(to: get_redirect_path(conn, params))
    else
      redirect(conn, to: ~q"/#{language}")
    end
  end

  def admin(conn, %{"locale" => locale}) do
    conn = if locale in Edenflowers.Locales.admin(), do: put_session(conn, "admin_locale", locale), else: conn
    redirect(conn, to: ~p"/admin/account")
  end

  defp get_redirect_path(conn, params) do
    with path when is_binary(path) <- params["redirect_to"] || referer_path(conn),
         true <- local_path?(path) do
      path
    else
      _ -> ~q"/#{language}"
    end
  end

  defp referer_path(conn) do
    with [referer] <- get_req_header(conn, "referer"),
         %URI{path: path} <- URI.parse(referer) do
      path
    else
      _ -> nil
    end
  end

  # Phoenix's redirect/2 raises on anything but a local path.
  defp local_path?("//" <> _), do: false
  defp local_path?("/" <> _ = path), do: not String.contains?(path, "\\")
  defp local_path?(_), do: false
end
