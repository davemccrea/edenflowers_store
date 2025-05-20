defmodule EdenflowersWeb.OrderLive do
  use EdenflowersWeb, :live_view

  on_mount {EdenflowersWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash}>
      <div class="container my-36">
        <h1>{gettext("Order #1234")}</h1>
      </div>
    </Layouts.app>
    """
  end
end
