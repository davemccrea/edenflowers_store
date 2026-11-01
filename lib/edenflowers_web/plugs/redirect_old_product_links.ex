defmodule EdenflowersWeb.Plugs.RedirectOldProductLinks do
  @moduledoc """
  Permanently redirects a product page reached by its id or a former slug, as
  in links shared before slugs existed or before Jennie changed one, to the
  page at its current slug. Search engines then move to the new URL. A plug
  rather than the LiveView, which can only redirect temporarily.
  """

  import Plug.Conn

  alias Edenflowers.Catalog
  alias EdenflowersWeb.Store.ProductLive

  def init(opts), do: opts

  def call(%{private: %{phoenix_live_view: {ProductLive, _, _}}, path_params: %{"slug" => param}} = conn, _opts) do
    case Catalog.current_product_slug(param) do
      {:ok, slug} when is_binary(slug) and slug != param -> redirect_to(conn, slug)
      _ -> conn
    end
  end

  def call(conn, _opts), do: conn

  defp redirect_to(conn, slug) do
    path = conn.request_path |> Path.dirname() |> Path.join(slug)
    path = if conn.query_string == "", do: path, else: path <> "?" <> conn.query_string

    conn
    |> put_status(:moved_permanently)
    |> Phoenix.Controller.redirect(to: path)
    |> halt()
  end
end
