defmodule EdenflowersWeb.CondolencesLive do
  use EdenflowersWeb, :live_view

  on_mount {EdenflowersWeb.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <p class="eyebrow text-base-content/60 mb-8 md:mb-12">{~t"Occasions"}</p>
        <h1 class="page-title">{~t"Condolences"}</h1>
      </.container>
    </Layouts.app>
    """
  end
end
