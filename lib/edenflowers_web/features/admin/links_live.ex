defmodule EdenflowersWeb.Admin.LinksLive do
  @moduledoc """
  Admin and dev links for running Eden Flowers. Link labels stay in English: the page is mostly for the developer.
  """

  use EdenflowersWeb, {:live_view, gettext_domain: "admin"}

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: ~t"Links", sections: sections())}
  end

  defp sections do
    [
      {~t"System",
       [
         {"Errors", "/admin/errors"},
         {"Oban jobs", "/admin/oban"},
         {"AshAdmin", "/admin/ash"}
       ]},
      {~t"Finances",
       [
         {"Stripe", "https://dashboard.stripe.com"},
         {"Papra documents", "https://papra.edenflowers.fi"}
       ]},
      {~t"Email and marketing", [{"Brevo", "https://app.brevo.com"}]},
      {~t"Hosting",
       [
         {"Cloudflare", "https://dash.cloudflare.com"},
         {"Tailscale", "https://console.tailscale.com/"},
         {"Better Stack", "https://incidents.betterstack.com"},
         {"GitHub", "https://github.com/davemccrea/edenflowers_store"},
         {"Container images", "https://github.com/davemccrea/edenflowers_store/pkgs/container/edenflowers_store"}
       ]},
      {~t"APIs",
       [
         {"Mapbox", "https://console.mapbox.com"},
         {"HERE", "https://platform.here.com"},
         {"Anthropic console", "https://console.anthropic.com"}
       ]}
    ]
    |> Enum.map(fn {title, links} ->
      {title, Enum.map(links, fn {label, url} -> {label, url, URI.parse(url).host} end)}
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={~t"Links"} />

        <div class="gap-4 sm:columns-2 xl:columns-3">
          <section :for={{title, links} <- @sections} class="admin-card mb-4 break-inside-avoid">
            <h2 class="text-base-content/60 px-4 pt-3 pb-1 text-xs font-semibold uppercase tracking-wide">
              {title}
            </h2>
            <ul class="divide-base-content/8 divide-y">
              <li :for={{label, url, host} <- links}>
                <a
                  href={url}
                  target={host && "_blank"}
                  rel={host && "noopener noreferrer"}
                  class="group min-h-12 flex items-center gap-3 px-4 py-2 hover:bg-base-200"
                >
                  <span class="min-w-0 flex-1">
                    <span class="block font-semibold">{label}</span>
                    <span :if={host} class="text-base-content/50 block truncate text-xs">{host}</span>
                  </span>
                  <.icon
                    name={if host, do: "hero-arrow-top-right-on-square", else: "hero-chevron-right"}
                    class="text-base-content/40 size-4 shrink-0 group-hover:text-base-content"
                  />
                </a>
              </li>
            </ul>
          </section>
        </div>
      </.admin_page>
    </Layouts.admin>
    """
  end
end
