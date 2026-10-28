defmodule EdenflowersWeb.Admin.LinksLive do
  @moduledoc """
  Admin and dev links for running Eden Flowers, rendered from `links.md` next to this module.
  """

  use EdenflowersWeb, {:live_view, gettext_domain: "admin"}

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @links_path Path.join(__DIR__, "links.md")
  @external_resource @links_path
  @links_html MDEx.to_html!(File.read!(@links_path))

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, ~t"Links")}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :links_html, @links_html)

    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={~t"Links"} />

        <section class="admin-card [&_a]:link [&_a]:link-primary [&_h2]:mb-2 [&_h2]:font-semibold [&_h2:not(:first-child)]:mt-5 [&_li]:py-0.5 p-4 sm:p-5">
          {Phoenix.HTML.raw(@links_html)}
        </section>
      </.admin_page>
    </Layouts.admin>
    """
  end
end
