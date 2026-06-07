defmodule EdenflowersWeb.Admin.DeliveriesLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  require Ash.Query

  alias EdenflowersWeb.Layouts
  alias Edenflowers.Delivery.{Driver, Route, RouteStop}
  alias Edenflowers.Store.Order
  alias Edenflowers.TourPlanning.Solver

  on_mount {EdenflowersWeb.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(_params, _session, socket) do
    today = DateTime.now!("Europe/Helsinki") |> DateTime.to_date()

    {:ok,
     socket
     |> assign(:page_title, ~t"Plan deliveries")
     |> assign(:date, today)
     |> assign(:optimizing?, false)
     |> assign(:publishing?, false)
     |> assign(:subscribed_route_ids, MapSet.new())
     |> assign(:routes, nil)
     |> assign(:plan_error, nil)
     |> load_planning_data()}
  end

  # The eligible set and the published routes are both day-scoped and both shift when a run is
  # published, so they reload together. Selecting always starts from a clean slate: every still-
  # eligible order picked, the driver default, no draft.
  defp load_planning_data(socket) do
    actor = socket.assigns.current_user
    orders = Order.list_eligible_for_delivery!(%{date: socket.assigns.date}, actor: actor)
    drivers = Driver.list_active!(actor: actor)
    published_routes = Route.list_published_for_date!(socket.assigns.date, actor: actor)

    socket
    |> assign(:eligible_orders, orders)
    |> assign(:drivers, drivers)
    |> assign(:published_routes, published_routes)
    |> assign(:order_by_id, Map.new(orders, &{&1.id, &1}))
    |> assign(:driver_by_id, Map.new(drivers, &{&1.id, &1}))
    |> assign(:selected_order_ids, MapSet.new(Enum.map(orders, & &1.id)))
    |> assign(:selected_driver_ids, default_driver_selection(drivers))
    |> assign(:routes, nil)
    |> assign(:plan_error, nil)
    |> subscribe_to_routes(published_routes)
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

        <section :if={@published_routes != []} class="mb-8 space-y-4">
          <h2 class="text-sm font-semibold">{~t"Published routes"}</h2>

          <article
            :for={route <- @published_routes}
            id={"route-monitor-#{route.id}"}
            class="border-base-300/70 bg-base-200/40 rounded-lg border p-4"
          >
            <header class="mb-4 flex flex-wrap items-start justify-between gap-3">
              <div>
                <div class="flex flex-wrap items-center gap-2">
                  <h3 class="font-medium">{route.driver.name}</h3>
                  <span
                    :if={route_complete?(route)}
                    class="badge badge-sm badge-success admin-badge-success"
                  >
                    {~t"Completed"}
                  </span>
                </div>
                <p class="text-base-content/65 mt-1 text-sm">
                  {length(route.route_stops)} {~t"stops"}
                </p>
              </div>

              <div class="flex flex-wrap gap-2">
                <button
                  type="button"
                  id={"copy-route-#{route.id}"}
                  phx-hook="CopyToClipboard"
                  data-clipboard-text={driver_link(route.driver)}
                  data-copied-label={~t"Copied!"}
                  class="btn btn-ghost btn-xs"
                >
                  <.icon name="hero-link" class="h-4 w-4" />
                  <span data-copy-label>{~t"Copy link"}</span>
                </button>
                <a
                  href={~p"/d/#{route.driver.link_token}"}
                  target="_blank"
                  rel="noopener"
                  class="btn btn-ghost btn-xs"
                >
                  <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" />
                  {~t"Open driver view"}
                </a>
              </div>
            </header>

            <% progress = route_progress(route) %>
            <div
              id={"route-progress-#{route.id}"}
              class="mb-3 flex flex-wrap gap-x-4 gap-y-1 text-sm"
            >
              <span id={"route-delivered-#{route.id}"}>
                <span class="font-medium">{progress.delivered}</span>
                <span class="text-base-content/65">{~t"Delivered"}</span>
              </span>
              <span id={"route-failed-#{route.id}"}>
                <span class="font-medium">{progress.failed}</span>
                <span class="text-base-content/65">{~t"Failed"}</span>
              </span>
              <span id={"route-remaining-#{route.id}"}>
                <span class="font-medium">{progress.remaining}</span>
                <span class="text-base-content/65">{~t"Remaining"}</span>
              </span>
            </div>

            <ol class="divide-base-300/70 divide-y">
              <li
                :for={stop <- route.route_stops}
                id={"monitor-stop-#{stop.id}"}
                class="flex items-baseline justify-between gap-3 py-2"
              >
                <span class="flex items-baseline gap-2">
                  <span class="text-base-content/50 w-5 text-sm">{stop.sequence}.</span>
                  <span class="font-medium">{stop.order_reference}</span>
                  <span class="text-base-content/65 text-sm">{stop.recipient_name}</span>
                </span>
                <span class="flex items-center gap-3 whitespace-nowrap text-sm">
                  <span class={stop_status_class(stop.status)}>
                    {stop_status_label(stop.status)}
                  </span>
                  <span class="text-base-content/65">{format_km(stop.leg_distance_m)} km</span>
                </span>
              </li>
            </ol>
          </article>
        </section>

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
          <header class="flex flex-wrap items-center justify-between gap-2">
            <h2 class="text-sm font-semibold">{~t"Proposed routes"}</h2>
            <button
              type="button"
              phx-click="publish"
              disabled={@publishing?}
              class="btn btn-primary btn-sm"
            >
              <span :if={@publishing?} class="loading loading-spinner loading-xs"></span>
              {if @publishing?, do: ~t"Publishing…", else: ~t"Publish run"}
            </button>
          </header>

          <article :for={route <- @routes} class="border-base-300/70 rounded-lg border p-4">
            <header class="mb-3 flex flex-wrap items-baseline justify-between gap-2">
              <h3 class="font-medium">{driver_name(assigns, route.driver_id)}</h3>
              <p class="text-base-content/65 text-sm">
                {length(route.stops)} {~t"stops"} · {format_km(route.total_distance_m)} km · {~t"drive"} {format_duration(
                  route.total_driving_s
                )} · {~t"total"} {format_duration(route.total_duration_s)}
              </p>
            </header>

            <ol class="divide-base-300/70 divide-y">
              <li :for={stop <- route.stops} class="flex items-baseline justify-between gap-3 py-2">
                <span class="flex items-baseline gap-2">
                  <span class="text-base-content/50 w-5 text-sm">{stop.sequence}.</span>
                  <span class="font-medium">{order_label(assigns, stop.stop_id)}</span>
                </span>
                <span class="text-base-content/65 whitespace-nowrap text-sm">
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

  def handle_event("publish", _params, socket) do
    if socket.assigns.routes && not socket.assigns.publishing? do
      send(self(), :run_publish)
      {:noreply, assign(socket, publishing?: true)}
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

  # Like the solve, publishing runs in handle_info so the disabled button renders first. It
  # persists the reviewed draft as Route + RouteStop rows in one transaction, then reloads the
  # day's eligible orders and published routes from scratch.
  def handle_info(:run_publish, socket) do
    case publish_run(socket) do
      {:ok, _routes} ->
        {:noreply,
         socket
         |> assign(:publishing?, false)
         |> load_planning_data()
         |> put_flash(:info, ~t"Routes published.")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:publishing?, false)
         |> put_flash(:error, ~t"The routes couldn't be published. Nothing was saved. Try again.")}
    end
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          payload: %Ash.Notifier.Notification{data: %RouteStop{} = updated_stop}
        },
        socket
      ) do
    published_routes =
      Enum.map(socket.assigns.published_routes, fn route ->
        if route.id == updated_stop.route_id do
          %{route | route_stops: replace_stop(route.route_stops, updated_stop)}
        else
          route
        end
      end)

    {:noreply, assign(socket, :published_routes, published_routes)}
  end

  # All-or-nothing: every route for the run is created inside one transaction, so a failure on
  # any of them raises, rolls back the rest, and persists nothing.
  defp publish_run(socket) do
    %{routes: routes, date: date, current_user: actor} = socket.assigns
    orders = load_orders_for_snapshot(routes, actor)

    Ash.transaction(Route, fn ->
      Enum.each(routes, fn route ->
        stops = Enum.map(route.stops, &stop_args(&1, Map.fetch!(orders, &1.stop_id)))
        Route.publish!(%{date: date, driver_id: route.driver_id, stops: stops}, actor: actor)
      end)
    end)
  rescue
    error -> {:error, error}
  end

  defp load_orders_for_snapshot(routes, actor) do
    order_ids = routes |> Enum.flat_map(& &1.stops) |> Enum.map(& &1.stop_id) |> Enum.uniq()

    Order
    |> Ash.Query.filter(id in ^order_ids)
    |> Ash.Query.load(:line_items)
    |> Ash.read!(actor: actor)
    |> Map.new(&{&1.id, &1})
  end

  defp stop_args(solved_stop, order) do
    %{
      sequence: solved_stop.sequence,
      order_id: order.id,
      order_reference: order.order_reference,
      recipient_name: order.recipient_name,
      recipient_phone: order.recipient_phone_number,
      delivery_address: order.delivery_address,
      delivery_instructions: order.delivery_instructions,
      card_message: order.card_message,
      products: product_lines(order),
      position: order.position,
      leg_distance_m: solved_stop.leg_from_previous.distance_m,
      leg_duration_s: solved_stop.leg_from_previous.duration_s
    }
  end

  # The card is snapshotted as a message, not a product line; the driver never sees prices.
  defp product_lines(order) do
    order.line_items
    |> Enum.reject(& &1.is_card)
    |> Enum.map(&%{"name" => &1.product_name, "quantity" => &1.quantity})
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

  defp subscribe_to_routes(socket, routes) do
    if connected?(socket) do
      subscribed_route_ids =
        Enum.reduce(routes, socket.assigns.subscribed_route_ids, fn route, subscribed ->
          if MapSet.member?(subscribed, route.id) do
            subscribed
          else
            EdenflowersWeb.Endpoint.subscribe("route_stop:outcome:#{route.id}")
            MapSet.put(subscribed, route.id)
          end
        end)

      assign(socket, :subscribed_route_ids, subscribed_route_ids)
    else
      socket
    end
  end

  defp replace_stop(stops, updated_stop) do
    Enum.map(stops, fn stop ->
      if stop.id == updated_stop.id, do: updated_stop, else: stop
    end)
  end

  defp route_progress(route) do
    counts = Enum.frequencies_by(route.route_stops, & &1.status)

    %{
      delivered: Map.get(counts, :delivered, 0),
      failed: Map.get(counts, :failed, 0),
      remaining: Map.get(counts, :pending, 0)
    }
  end

  defp route_complete?(route) do
    route.route_stops != [] and
      Enum.all?(route.route_stops, &(&1.status in [:delivered, :skipped]))
  end

  defp driver_link(driver), do: EdenflowersWeb.Endpoint.url() <> "/d/" <> driver.link_token

  defp stop_status_label(:pending), do: ~t"Pending"
  defp stop_status_label(:delivered), do: ~t"Delivered"
  defp stop_status_label(:failed), do: ~t"Failed"
  defp stop_status_label(:skipped), do: ~t"Skipped"

  defp stop_status_class(:pending), do: "badge badge-sm admin-badge-neutral"
  defp stop_status_class(:delivered), do: "badge badge-sm badge-success admin-badge-success"
  defp stop_status_class(:failed), do: "badge badge-sm badge-error"
  defp stop_status_class(:skipped), do: "badge badge-sm admin-badge-neutral"

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
