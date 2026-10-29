defmodule EdenflowersWeb.Marketing.LegacyRedirectController do
  @moduledoc """
  Sends welcome pages from the old site, still linked from Stormossen's Minimossen
  pages, permanently to the home page in the same language.
  """
  use EdenflowersWeb, :controller

  def swedish(conn, _params), do: moved_permanently(conn, "/sv")

  def finnish(conn, _params), do: moved_permanently(conn, "/fi")

  defp moved_permanently(conn, path) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: path)
  end
end
