defmodule EdenflowersWeb.OrderLive do
  use EdenflowersWeb, :live_view

  alias Edenflowers.Store.Order

  on_mount {EdenflowersWeb.LiveUserAuth, :live_user_required}

  def mount(%{"id" => order_id}, _session, socket) do
    case Order.get_for_confirmation(order_id, actor: socket.assigns.current_user) do
      {:ok, order} ->
        {:ok, assign(socket, order: order, page_title: "##{order.order_reference}")}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, ~t"Order not found")
         |> push_navigate(to: ~p"/")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} cart={@cart} flash={@flash} current_path={@current_path}>
      <.container>
        <h1>{~t"Order"} #{@order.order_reference}</h1>
      </.container>
    </Layouts.app>
    """
  end
end
