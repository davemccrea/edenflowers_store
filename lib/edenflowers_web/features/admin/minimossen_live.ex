defmodule EdenflowersWeb.Admin.MinimossenLive do
  @moduledoc """
  Minimossen's sales across the page's full width, the same as the Overview's card,
  with the card's choices in the URL.
  """

  use EdenflowersWeb, {:live_view, gettext_domain: "admin"}

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Admin.MinimossenCard
  alias EdenflowersWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: ~t"Minimossen", locale: Localize.get_locale())}
  end

  # A choice that doesn't parse falls back to the card's default.
  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     assign(socket,
       period: Map.get(%{"month" => :month, "year" => :year}, params["period"], :week),
       group: params["group"],
       at: date(params["at"])
     )}
  end

  defp date(nil), do: nil

  defp date(iso) do
    case Date.from_iso8601(iso) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={~t"Minimossen"}>
          <:actions>
            <nav class="flex gap-1" aria-label={~t"Show sales by"}>
              <.link
                :for={{period, label} <- MinimossenCard.period_choices()}
                patch={MinimossenCard.path(period: period, group: @group)}
                aria-current={period == @period && "page"}
                class="btn btn-sm rounded-full font-normal shadow-none aria-[current=page]:btn-primary not-aria-[current=page]:btn-ghost"
              >
                {label}
              </.link>
            </nav>
          </:actions>
        </.admin_page_header>
        <.live_component
          module={MinimossenCard}
          id="minimossen-card"
          current_user={@current_user}
          locale={@locale}
          period={@period}
          group={@group}
          at={@at}
          wide
        />
      </.admin_page>
    </Layouts.admin>
    """
  end
end
