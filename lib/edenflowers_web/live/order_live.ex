defmodule EdenflowersWeb.OrderLive do
  use EdenflowersWeb, :live_view

  on_mount {EdenflowersWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <.link
          navigate={~p"/account"}
          class="eyebrow text-base-content/70 link-underline-hover-nav mb-5 inline-block w-fit"
        >
          {~t"Your account"}
        </.link>
        <h1 class="page-title">{~t"Order #1234"}</h1>
      </.container>
    </Layouts.app>
    """
  end
end
