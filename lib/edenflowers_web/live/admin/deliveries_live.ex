defmodule EdenflowersWeb.Admin.DeliveriesLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Layouts
  alias Edenflowers.Delivery.Driver
  alias Edenflowers.Store.Order

  on_mount {EdenflowersWeb.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(_params, _session, socket) do
    actor = socket.assigns.current_user
    orders = Order.list_eligible_for_delivery!(%{}, actor: actor)
    drivers = Driver.list_active!(actor: actor)

    {:ok,
     socket
     |> assign(:page_title, ~t"Plan deliveries")
     |> assign(:eligible_orders, orders)
     |> assign(:drivers, drivers)
     |> assign(:selected_order_ids, MapSet.new(Enum.map(orders, & &1.id)))
     |> assign(:selected_driver_ids, default_driver_selection(drivers))}
  end

  # With a single active driver there is no choice to make, so pre-select it; otherwise
  # leave the pool empty for the florist to choose from.
  defp default_driver_selection([driver]), do: MapSet.new([driver.id])
  defp default_driver_selection(_drivers), do: MapSet.new()

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page width="full">
        <.admin_page_header title={~t"Plan deliveries"}>
          <:subtitle>{~t"Choose today's orders and the drivers available, then optimize the routes."}</:subtitle>
        </.admin_page_header>

        <div
          :if={@eligible_orders == []}
          class="border-base-300/70 rounded-lg border border-dashed p-10 text-center"
        >
          <p class="text-base-content/65 text-sm">
            {~t"No deliveries to plan today."}
          </p>
        </div>

        <div :if={@eligible_orders != []} class="grid gap-6 lg:grid-cols-3">
          <section class="lg:col-span-2">
            <h2 class="mb-2 text-sm font-semibold">
              {~t"Orders"} ({MapSet.size(@selected_order_ids)}/{length(@eligible_orders)})
            </h2>
            <div class="border-base-300/70 overflow-x-auto rounded-lg border">
              <table class="table">
                <thead>
                  <tr>
                    <th class="w-10"></th>
                    <th>{~t"Order"}</th>
                    <th>{~t"Recipient"}</th>
                    <th class="text-right">{~t"Distance"}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={order <- @eligible_orders}>
                    <td>
                      <input
                        type="checkbox"
                        class="checkbox checkbox-sm"
                        id={"order-#{order.id}"}
                        phx-click="toggle_order"
                        phx-value-id={order.id}
                        checked={MapSet.member?(@selected_order_ids, order.id)}
                      />
                    </td>
                    <td class="font-medium">{order.order_reference}</td>
                    <td>{order.recipient_name || order.customer_name}</td>
                    <td class="text-right">
                      <span :if={order.distance_km}>{order.distance_km} km</span>
                      <span :if={is_nil(order.distance_km)} class="text-base-content/30">—</span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>

          <section>
            <h2 class="mb-2 text-sm font-semibold">
              {~t"Drivers"} ({MapSet.size(@selected_driver_ids)}/{length(@drivers)})
            </h2>

            <div
              :if={@drivers == []}
              class="border-base-300/70 rounded-lg border border-dashed p-6 text-center"
            >
              <p class="text-base-content/65 text-sm">
                {~t"No active drivers. Add one before planning."}
              </p>
            </div>

            <ul :if={@drivers != []} class="border-base-300/70 divide-base-300/70 divide-y rounded-lg border">
              <li :for={driver <- @drivers}>
                <label for={"driver-#{driver.id}"} class="flex cursor-pointer items-center gap-3 p-3">
                  <input
                    type="checkbox"
                    class="checkbox checkbox-sm"
                    id={"driver-#{driver.id}"}
                    phx-click="toggle_driver"
                    phx-value-id={driver.id}
                    checked={MapSet.member?(@selected_driver_ids, driver.id)}
                  />
                  <span class="text-sm font-medium">{driver.name}</span>
                </label>
              </li>
            </ul>
          </section>
        </div>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("toggle_order", %{"id" => id}, socket) do
    {:noreply, update(socket, :selected_order_ids, &toggle(&1, id))}
  end

  def handle_event("toggle_driver", %{"id" => id}, socket) do
    {:noreply, update(socket, :selected_driver_ids, &toggle(&1, id))}
  end

  defp toggle(set, id) do
    if MapSet.member?(set, id), do: MapSet.delete(set, id), else: MapSet.put(set, id)
  end
end
