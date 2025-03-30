defmodule EdenflowersWeb.CoursesLive do
  use EdenflowersWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="container">
      <h1 class="font-serif text-4xl">Courses</h1>
    </div>
    """
  end
end
