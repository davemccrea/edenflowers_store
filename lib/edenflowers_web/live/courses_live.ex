defmodule EdenflowersWeb.CoursesLive do
  use EdenflowersWeb, :live_view

  on_mount {EdenflowersWeb.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    upcoming_courses =
      Edenflowers.Services.Course.list_upcoming_courses!(load: [:total_registrations])

    socket =
      socket
      |> assign(upcoming_courses: upcoming_courses)

    {:ok, socket}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash}></Layouts.app>
    """
  end
end
