defmodule EdenflowersWeb.ContactLive do
  use EdenflowersWeb, :live_view

  on_mount {EdenflowersWeb.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash}>
      <.container>
        <h1 class="font-serif text-4xl">{gettext("Contact")}</h1>
      </.container>
    </Layouts.app>
    """
  end
end
