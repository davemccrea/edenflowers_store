defmodule EdenflowersWeb.Admin.MinimossenLive do
  @moduledoc """
  Minimossen's sales across the page's full width, by week or month and for all
  product groups or one, with the choices in the URL.
  """

  use EdenflowersWeb, {:live_view, gettext_domain: "admin"}

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Minimossen
  alias EdenflowersWeb.Admin.MinimossenCard
  alias EdenflowersWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: ~t"Minimossen", locale: Localize.get_locale())}
  end

  # A period that doesn't parse falls back to weeks.
  @impl true
  def handle_params(params, _uri, socket) do
    period = if params["period"] == "month", do: :month, else: :week
    # This year's months, January on.
    arguments = [period: period, this_year: period == :month]
    sales = Minimossen.recent_minimossen_sales!(arguments, actor: socket.assigns.current_user)
    {:noreply, assign(socket, period: period, group: params["group"], sales: sales)}
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
                patch={MinimossenCard.page_path(period, @group)}
                aria-current={period == @period && "page"}
                class="btn btn-sm rounded-full font-normal shadow-none aria-[current=page]:btn-primary not-aria-[current=page]:btn-ghost"
              >
                {label}
              </.link>
            </nav>
          </:actions>
        </.admin_page_header>
        <.widget id="minimossen">
          <MinimossenCard.sales
            :if={@sales.periods != []}
            period={@period}
            sales={@sales}
            group={@group}
            locale={@locale}
            wide
          />
          <p :if={@sales.periods == []} class="text-base-content/75 text-sm">
            {~t"No Winpos reports imported yet."}
          </p>
        </.widget>
      </.admin_page>
    </Layouts.admin>
    """
  end
end
