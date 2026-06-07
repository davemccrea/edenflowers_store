defmodule EdenflowersWeb.Admin.DeliveriesLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Layouts
  alias Edenflowers.Delivery.Driver
  alias Edenflowers.Store.Order
  alias Edenflowers.TourPlanning.Solver

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
     |> assign(:order_by_id, Map.new(orders, &{&1.id, &1}))
     |> assign(:driver_by_id, Map.new(drivers, &{&1.id, &1}))
     |> assign(:selected_order_ids, MapSet.new(Enum.map(orders, & &1.id)))
     |> assign(:selected_driver_ids, default_driver_selection(drivers))
     |> assign(:optimizing?, false)
     |> assign(:routes, nil)
     |> assign(:plan_error, nil)}
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
          <:actions>
            <button
              type="button"
              phx-click="optimize"
              disabled={not can_optimize?(assigns)}
              class="btn btn-primary btn-sm"
            >
              <span :if={@optimizing?} class="loading loading-spinner loading-xs"></span>
              {if @optimizing?, do: ~t"Optimizing…", else: ~t"Optimize"}
            </button>
          </:actions>
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

        <div :if={@plan_error == :unassigned} class="alert alert-warning mt-6" role="alert">
          <.icon name="hero-exclamation-triangle" class="h-5 w-5" />
          <span>
            {~t"Some orders couldn't be placed with the selected drivers. Adjust the orders or drivers and optimize again."}
          </span>
        </div>

        <div :if={@plan_error == :failed} class="alert alert-error mt-6" role="alert">
          <.icon name="hero-exclamation-triangle" class="h-5 w-5" />
          <span>{~t"The optimizer couldn't be reached. Try again."}</span>
        </div>

        <section :if={@routes} class="mt-8 space-y-6">
          <h2 class="text-sm font-semibold">{~t"Proposed routes"}</h2>

          <article :for={route <- @routes} class="border-base-300/70 rounded-lg border p-4">
            <header class="mb-3 flex flex-wrap items-baseline justify-between gap-2">
              <h3 class="font-medium">{driver_name(assigns, route.driver_id)}</h3>
              <p class="text-base-content/65 text-sm">
                {length(route.stops)} {~t"stops"} · {format_km(route.total_distance_m)} km ·
                {~t"drive"} {format_duration(route.total_driving_s)} ·
                {~t"total"} {format_duration(route.total_duration_s)}
              </p>
            </header>

            <ol class="divide-base-300/70 divide-y">
              <li :for={stop <- route.stops} class="flex items-baseline justify-between gap-3 py-2">
                <span class="flex items-baseline gap-2">
                  <span class="text-base-content/50 w-5 text-sm">{stop.sequence}.</span>
                  <span class="font-medium">{order_label(assigns, stop.stop_id)}</span>
                </span>
                <span class="text-base-content/65 text-sm whitespace-nowrap">
                  +{format_km(stop.leg_from_previous.distance_m)} km · +{format_duration(stop.leg_from_previous.duration_s)}
                </span>
              </li>
            </ol>
          </article>

          <div :if={unused_drivers(assigns) != []} class="text-base-content/65 text-sm">
            {~t"Not used by the optimizer:"} {unused_drivers(assigns) |> Enum.map_join(", ", & &1.name)}
          </div>
        </section>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("toggle_order", %{"id" => id}, socket) do
    {:noreply, socket |> update(:selected_order_ids, &toggle(&1, id)) |> discard_draft()}
  end

  def handle_event("toggle_driver", %{"id" => id}, socket) do
    {:noreply, socket |> update(:selected_driver_ids, &toggle(&1, id)) |> discard_draft()}
  end

  def handle_event("optimize", _params, socket) do
    if can_optimize?(socket.assigns) do
      send(self(), :run_optimize)
      {:noreply, assign(socket, optimizing?: true, routes: nil, plan_error: nil)}
    else
      {:noreply, socket}
    end
  end

  # The solve runs in handle_info, not the click handler, so the disabled button and
  # spinner render first — the optimizer call (a real HTTP round-trip in production) then
  # blocks this process until it returns.
  @impl true
  def handle_info(:run_optimize, socket) do
    case Solver.solve(build_problem(socket)) do
      {:ok, routes} ->
        {:noreply, assign(socket, optimizing?: false, routes: routes, plan_error: nil)}

      {:error, :unassigned} ->
        {:noreply, assign(socket, optimizing?: false, routes: nil, plan_error: :unassigned)}

      {:error, _reason} ->
        {:noreply, assign(socket, optimizing?: false, routes: nil, plan_error: :failed)}
    end
  end

  defp build_problem(socket) do
    handling = Application.get_env(:edenflowers, :delivery_handling_seconds, 300)

    stops =
      socket.assigns.eligible_orders
      |> Enum.filter(&MapSet.member?(socket.assigns.selected_order_ids, &1.id))
      |> Enum.map(&%{id: &1.id, position: &1.position, handling_seconds: handling})

    drivers =
      socket.assigns.drivers
      |> Enum.filter(&MapSet.member?(socket.assigns.selected_driver_ids, &1.id))
      |> Enum.map(&%{id: &1.id})

    %{stops: stops, drivers: drivers}
  end

  defp can_optimize?(assigns) do
    not assigns.optimizing? and MapSet.size(assigns.selected_order_ids) > 0 and
      MapSet.size(assigns.selected_driver_ids) > 0
  end

  # A draft describes one specific set of orders and drivers; once that set changes it no
  # longer applies, so clear it and let the florist re-optimize.
  defp discard_draft(socket), do: assign(socket, routes: nil, plan_error: nil)

  defp driver_name(assigns, driver_id) do
    case assigns.driver_by_id[driver_id] do
      nil -> driver_id
      driver -> driver.name
    end
  end

  defp order_label(assigns, order_id) do
    case assigns.order_by_id[order_id] do
      nil -> order_id
      order -> order.order_reference <> " · " <> (order.recipient_name || order.customer_name || "")
    end
  end

  defp unused_drivers(assigns) do
    used = MapSet.new(assigns.routes || [], & &1.driver_id)

    assigns.drivers
    |> Enum.filter(&MapSet.member?(assigns.selected_driver_ids, &1.id))
    |> Enum.reject(&MapSet.member?(used, &1.id))
  end

  defp format_km(metres), do: :erlang.float_to_binary(metres / 1000, decimals: 1)

  defp format_duration(seconds) do
    minutes = div(seconds, 60)

    cond do
      minutes >= 60 -> "#{div(minutes, 60)}h #{rem(minutes, 60)}m"
      true -> "#{minutes}m"
    end
  end

  defp toggle(set, id) do
    if MapSet.member?(set, id), do: MapSet.delete(set, id), else: MapSet.put(set, id)
  end
end
