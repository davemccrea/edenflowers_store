defmodule EdenflowersWeb.AccountLive do
  use EdenflowersWeb, :live_view

  alias Edenflowers.Store.Order

  on_mount {EdenflowersWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    {:ok, socket |> assign(orders: Order.get_all_for_user!(socket.assigns.current_user.id))}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash}>
      <div class="container my-48">
        <p class="text-sm">{@current_user.name}</p>
        <p class="text-sm">{@current_user.email}</p>

        <section class="space-y-4">
          <h1 class="font-serif mt-8 text-2xl">Your Orders</h1>

          <div class="overflow-x-auto">
            <table class="table">
              <!-- head -->
              <thead>
                <tr>
                  <th>Order Reference</th>
                  <th>Date</th>
                  <th>Total</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                <!-- row 1 -->
                <tr :for={order <- @orders}>
                  <th>{order.id}</th>
                  <td>{order.inserted_at}</td>
                  <td>{order.total}</td>
                  <td>{order.fulfillment_status}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
