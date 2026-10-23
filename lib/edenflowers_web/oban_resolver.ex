defmodule EdenflowersWeb.ObanResolver do
  @moduledoc """
  Grants Oban Web access to signed-in admins and redirects everyone else to sign-in.
  """

  @behaviour Oban.Web.Resolver

  @impl Oban.Web.Resolver
  def resolve_user(conn), do: conn.assigns[:current_user]

  @impl Oban.Web.Resolver
  def resolve_access(%{admin: true}), do: :all
  def resolve_access(_user), do: {:forbidden, "/sign-in"}
end
