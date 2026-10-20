defmodule EdenflowersWeb.Admin.EmailsLive do
  @moduledoc """
  Every customer email in one language, rendered live from
  `Edenflowers.Email.Previews`, so Jennie can proofread the copy and its
  translations. The language is chosen here, apart from the admin's own.
  """

  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Email.Previews
  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @languages [{"en", "en-GB", "English"}, {"sv", "sv-FI", "Svenska"}, {"fi", "fi", "Suomi"}]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, ~t"Emails") |> assign(:languages, @languages)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {lang, locale, _name} = List.keyfind(@languages, params["lang"], 0, hd(@languages))

    email_types =
      locale
      |> Previews.all()
      |> Enum.chunk_by(fn {email_type, _, _, _} -> email_type end)
      |> Enum.sort_by(fn [{email_type, _, _, _} | _] -> Gettext.gettext(EdenflowersWeb.Gettext, email_type) end)

    {:noreply, socket |> assign(:lang, lang) |> assign(:email_types, email_types)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={~t"Emails"}>
          <:subtitle>{~t"Every email customers can get, with example details."}</:subtitle>
          <:actions>
            <div class="join">
              <button
                type="button"
                phx-click={JS.dispatch("details:open", to: "#emails details")}
                class="join-item btn btn-sm"
              >
                {~t"Expand all"}
              </button>
              <button
                type="button"
                phx-click={JS.dispatch("details:close", to: "#emails details")}
                class="join-item btn btn-sm"
              >
                {~t"Collapse all"}
              </button>
            </div>
            <div class="join">
              <.link
                :for={{lang, _locale, name} <- @languages}
                patch={~p"/admin/emails?lang=#{lang}"}
                lang={lang}
                aria-current={lang == @lang && "page"}
                class={["join-item btn btn-sm", lang == @lang && "btn-active"]}
              >
                {name}
              </.link>
            </div>
          </:actions>
        </.admin_page_header>

        <div id="emails" class="admin-card divide-base-content/8 divide-y">
          <details
            :for={{[{email_type, _, _, _} | _] = previews, type_index} <- Enum.with_index(@email_types)}
            id={"email-type-#{type_index}"}
            phx-mounted={JS.ignore_attributes(["open"])}
            class="group/type"
          >
            <summary class="text-base-content flex cursor-pointer list-none items-center gap-2 px-4 py-3 text-sm font-semibold hover:bg-base-300/40 sm:px-5">
              <.icon
                name="hero-chevron-right"
                class="text-base-content/50 h-4 w-4 shrink-0 transition-transform group-open/type:rotate-90"
              />
              <span>{Gettext.gettext(EdenflowersWeb.Gettext, email_type)}</span>
              <span class="text-base-content/65 ml-auto font-normal tabular-nums">{length(previews)}</span>
            </summary>
            <div class="border-base-content/8 divide-base-content/8 ml-6 divide-y border-t border-l sm:ml-7">
              <details
                :for={{{_, scenario, _, email}, scenario_index} <- Enum.with_index(previews)}
                id={"email-#{type_index}-#{scenario_index}"}
                phx-mounted={JS.ignore_attributes(["open"])}
                class="group/scenario"
              >
                <summary class="text-base-content/80 flex cursor-pointer list-none items-center gap-2 px-4 py-3 text-sm hover:bg-base-300/40 sm:px-5">
                  <.icon
                    name="hero-chevron-right"
                    class="text-base-content/50 h-4 w-4 shrink-0 transition-transform group-open/scenario:rotate-90"
                  />
                  <span class="first-letter:uppercase">{Gettext.gettext(EdenflowersWeb.Gettext, scenario)}</span>
                </summary>
                <div class="px-4 pb-4 pl-10 sm:px-5 sm:pl-11" lang={@lang}>
                  <p class="text-base-content mb-3 font-semibold">{email.subject}</p>
                  <pre class="text-base-content font-sans whitespace-pre-wrap text-sm leading-relaxed">{email.text_body}</pre>
                </div>
              </details>
            </div>
          </details>
        </div>
      </.admin_page>
    </Layouts.admin>
    """
  end
end
