defmodule EdenflowersWeb.Marketing.LegacyRedirectController do
  @moduledoc """
  Sends welcome pages from the old site, still linked from Stormossen's Minimossen
  pages, permanently to the home page in the same language. Also moves the
  privacy policy's untranslated Swedish and Finnish URLs to their translated ones.
  """
  use EdenflowersWeb, :controller

  def swedish(conn, _params), do: moved_permanently(conn, "/sv")

  def finnish(conn, _params), do: moved_permanently(conn, "/fi")

  def swedish_privacy(conn, _params), do: moved_permanently(conn, "/sv/integritetspolicy")

  def finnish_privacy(conn, _params), do: moved_permanently(conn, "/fi/tietosuojaseloste")

  defp moved_permanently(conn, path) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: path)
  end
end
