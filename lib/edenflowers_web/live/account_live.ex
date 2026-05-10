defmodule EdenflowersWeb.AccountLive do
  use EdenflowersWeb, :live_view

  alias Edenflowers.Store.Order

  on_mount {EdenflowersWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    orders = Order.get_all_completed!(socket.assigns.current_user.id, actor: socket.assigns.current_user)

    {:ok, assign(socket, orders: orders)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} cart={@cart} flash={@flash} current_path={@current_path}></Layouts.app>
    """
  end
end
