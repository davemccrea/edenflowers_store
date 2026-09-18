defmodule EdenflowersWeb.Marketing.CondolencesLive do
  use EdenflowersWeb, :live_view

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <h1 class="page-title mb-6">{~t"Condolences"}</h1>
        <p class="text-base-content/80 max-w-prose text-lg leading-relaxed">
          {~t"At a final farewell, let the flowers be a place for your eyes to rest. I create both traditional and personal funeral arrangements, and deliver to churches and chapels in Vaasa and Korsholm for a small fee."}
        </p>
      </.container>
    </Layouts.app>
    """
  end
end
