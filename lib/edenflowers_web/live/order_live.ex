defmodule EdenflowersWeb.OrderLive do
  use EdenflowersWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="container my-36">
        <h1>{gettext("Order #1234")}</h1>
      </div>
    </Layouts.app>
    """
  end
end
