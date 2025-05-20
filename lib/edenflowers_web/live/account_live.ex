defmodule EdenflowersWeb.AccountLive do
  use EdenflowersWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash}>
      <div class="container">
        <h1>Account</h1>
      </div>
    </Layouts.app>
    """
  end
end
