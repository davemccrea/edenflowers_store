defmodule EdenflowersWeb.CondolencesLive do
  use EdenflowersWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app order={@order} flash={@flash}>
      <div class="container my-36">
        <h1 class="font-serif text-4xl">{gettext("Condolences")}</h1>
      </div>
    </Layouts.app>
    """
  end
end
