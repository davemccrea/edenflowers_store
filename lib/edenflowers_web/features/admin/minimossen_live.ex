defmodule EdenflowersWeb.Admin.MinimossenLive do
  @moduledoc """
  Minimossen's sales across the page's full width, the same as the Overview's card.
  """

  use EdenflowersWeb, {:live_view, gettext_domain: "admin"}

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Admin.MinimossenCard
  alias EdenflowersWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: ~t"Minimossen", locale: Localize.get_locale())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={~t"Minimossen"} />
        <.live_component module={MinimossenCard} id="minimossen-card" current_user={@current_user} locale={@locale} wide />
      </.admin_page>
    </Layouts.admin>
    """
  end
end
