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
     |> assign(:optimization_strategy, :cheapest)
     |> assign(:optimizing?, false)
     |> assign(:publishing?, false)
     |> assign(:composer_collapsed?, false)
     |> assign(:subscribed_route_ids, MapSet.new())
     |> assign(:routes, nil)
     |> assign(:plan_error, nil)
     |> load_planning_data()}
  end

  # The eligible set and the published routes are both day-scoped and both shift when a run is
  # published, so they reload together. Selecting always starts from a clean slate: no orders,
  # the driver default, and no draft.
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
    |> assign(:selected_order_ids, MapSet.new())
    |> assign(:selected_driver_ids, default_driver_selection(drivers))
    |> assign(:routes, nil)
    |> assign(:plan_error, nil)
    |> assign(:composer_collapsed?, false)
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
        </.admin_page_header>

        <div
          :if={@eligible_orders == []}
          class="border-base-300/70 bg-base-100 mb-12 flex flex-col items-center gap-3 rounded-xl border border-dashed p-12 text-center"
        >
          <.icon name="hero-check-circle" class="text-base-content/30 h-8 w-8" />
          <p class="text-base-content/65 text-sm">
            {~t"No deliveries to plan today."}
          </p>
        </div>

        <section :if={@eligible_orders != []} class="mb-12">
          <.stage_header title={~t"Compose the run"} />

          <div class="border-base-300/70 bg-base-100 mb-6 flex flex-col gap-4 rounded-xl border p-4 sm:flex-row sm:items-center sm:justify-between">
            <dl class="flex flex-wrap items-baseline gap-x-6 gap-y-2">
              <.route_stat
                label={~t"Orders"}
                value={"#{MapSet.size(@selected_order_ids)} / #{length(@eligible_orders)}"}
              />
              <.route_stat
                label={~t"Drivers"}
                value={"#{MapSet.size(@selected_driver_ids)} / #{length(@drivers)}"}
              />
              <.route_stat label={~t"Strategy"} value={strategy_label(@optimization_strategy)} />
            </dl>
            <div class="flex items-center gap-2">
              <button
                :if={@routes}
                type="button"
                phx-click="toggle_composer"
                aria-expanded={to_string(not @composer_collapsed?)}
                aria-controls="composer-body"
                class="btn btn-ghost btn-sm"
              >
                <.icon
                  name={if @composer_collapsed?, do: "hero-chevron-down", else: "hero-chevron-up"}
                  class="h-4 w-4"
                />
                {if @composer_collapsed?, do: ~t"Edit selection", else: ~t"Hide selection"}
              </button>
              <button
                type="button"
                phx-click="optimize"
                disabled={not can_optimize?(assigns)}
                class={["btn btn-sm shrink-0 sm:btn-md", if(@routes, do: "btn-outline", else: "btn-primary")]}
              >
                <span :if={@optimizing?} class="loading loading-spinner loading-xs"></span>
                {if @optimizing?, do: ~t"Optimizing…", else: ~t"Optimize"}
              </button>
            </div>
          </div>

          <div
            :if={is_nil(@routes) or not @composer_collapsed?}
            id="composer-body"
            class="grid gap-6 lg:grid-cols-3"
          >
            <div class="lg:col-span-2">
              <p class="eyebrow text-base-content/65 mb-2">{~t"Orders"}</p>
              <div class="border-base-300/70 admin-table-scroll bg-base-100 overflow-x-auto rounded-xl border">
                <table class="table">
                  <thead>
                    <tr>
                      <th class="w-10">
                        <input
                          type="checkbox"
                          id="toggle-all-orders"
                          class="checkbox checkbox-sm"
                          phx-click="toggle_all_orders"
                          checked={all_orders_selected?(assigns)}
                          aria-label={~t"Select all orders"}
                        />
                      </th>
                      <th>{~t"Order"}</th>
                      <th>{~t"Recipient"}</th>
                      <th class="text-right">{~t"Distance"}</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr
                      :for={order <- @eligible_orders}
                      class={["transition-colors hover:bg-base-200/50", MapSet.member?(@selected_order_ids, order.id) && "bg-primary/5"]}
                    >
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
                      <td class="text-base-content/65 tabular-nums">{order.order_reference}</td>
                      <td class="font-medium">{order.recipient_name || order.customer_name}</td>
                      <td class="text-right tabular-nums">
                        <span :if={order.distance_km}>{format_distance_km(order.distance_km)}</span>
                        <span :if={is_nil(order.distance_km)} class="text-base-content/30">—</span>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>

            <div class="space-y-6">
              <fieldset>
                <legend class="eyebrow text-base-content/65 mb-2">{~t"Optimization"}</legend>
                <form id="optimization-strategy" phx-change="change_optimization">
                  <div class="border-base-300/70 divide-base-300/70 bg-base-100 divide-y overflow-hidden rounded-xl border">
                    <.optimization_option
                      value="cheapest"
                      title={~t"Cheapest"}
                      desc={~t"least total driving distance."}
                      checked={@optimization_strategy == :cheapest}
                    />
                    <.optimization_option
                      value="balanced"
                      title={~t"Balanced"}
                      desc={~t"equalizes total route duration across drivers."}
                      checked={@optimization_strategy == :balanced}
                    />
                    <.optimization_option
                      value="fastest"
                      title={~t"Fastest"}
                      desc={~t"minimizes aggregate driving and delivery time."}
                      checked={@optimization_strategy == :fastest}
                    />
                  </div>
                </form>
              </fieldset>

              <div>
                <p class="eyebrow text-base-content/65 mb-2">{~t"Drivers"}</p>

                <div
                  :if={@drivers == []}
                  class="border-base-300/70 rounded-xl border border-dashed p-6 text-center"
                >
                  <p class="text-base-content/65 text-sm">
                    {~t"No active drivers. Add one before planning."}
                  </p>
                </div>

                <ul
                  :if={@drivers != []}
                  class="border-base-300/70 divide-base-300/70 bg-base-100 divide-y overflow-hidden rounded-xl border"
                >
                  <li :for={driver <- @drivers}>
                    <label
                      for={"driver-#{driver.id}"}
                      class="flex cursor-pointer items-center gap-3 p-3.5 transition-colors hover:bg-base-200/50"
                    >
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
              </div>
            </div>
          </div>
        </section>

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

        <section :if={@routes} class="mb-12">
          <.stage_header title={~t"Proposed routes"}>
            <:actions>
              <button
                type="button"
                phx-click="publish"
                disabled={@publishing?}
                class="btn btn-primary btn-sm"
              >
                <span :if={@publishing?} class="loading loading-spinner loading-xs"></span>
                {if @publishing?, do: ~t"Publishing…", else: ~t"Publish run"}
              </button>
            </:actions>
          </.stage_header>

          <div class="space-y-4">
            <.proposed_route_card
              :for={route <- @routes}
              route={route}
              drivers={selected_drivers(assigns)}
              order_by_id={@order_by_id}
            />
          </div>

          <div :if={unused_drivers(assigns) != []} class="text-base-content/65 mt-4 text-sm">
            {~t"Not used by the optimizer:"} {unused_drivers(assigns) |> Enum.map_join(", ", & &1.name)}
          </div>
        </section>

        <section :if={@published_routes != []}>
          <.stage_header title={~t"Published routes"} />
          <div class="space-y-4">
            <.published_driver_card
              :for={{driver, routes} <- routes_by_driver(@published_routes)}
              driver={driver}
              routes={routes}
            />
          </div>
        </section>
      </.admin_page>
    </Layouts.admin>
    """
  end

  # Section heading with room for a right-aligned action (the publish button on the
  # review stage).
  attr :title, :string, required: true
  slot :actions

  defp stage_header(assigns) do
    ~H"""
    <div class="border-base-300/70 mb-5 flex flex-wrap items-end justify-between gap-3 border-b pb-3">
      <h2 class="text-base-content text-lg font-semibold tracking-tight">{@title}</h2>
      <div :if={@actions != []} class="flex items-center gap-2">{render_slot(@actions)}</div>
    </div>
    """
  end

  # Label-over-value metric used in the run command bar and on each proposed route.
  attr :label, :string, required: true
  attr :value, :any, required: true

  defp route_stat(assigns) do
    ~H"""
    <div class="flex items-baseline gap-1.5">
      <dt class="text-base-content/65">{@label}</dt>
      <dd class="text-base-content tabular-nums">{@value}</dd>
    </div>
    """
  end

  # One optimization strategy. The checked option carries a faint primary wash so the
  # active choice is legible without leaning on the radio dot alone.
  attr :value, :string, required: true
  attr :title, :string, required: true
  attr :desc, :string, required: true
  attr :checked, :boolean, required: true

  defp optimization_option(assigns) do
    ~H"""
    <label class={["flex cursor-pointer items-start gap-3 p-3.5 transition-colors", if(@checked, do: "bg-primary/5", else: "hover:bg-base-200/50")]}>
      <input
        type="radio"
        class="radio radio-sm radio-primary mt-0.5"
        name="optimization[strategy]"
        value={@value}
        checked={@checked}
      />
      <span class="min-w-0">
        <span class={["block text-sm font-medium", @checked && "text-primary"]}>{@title}</span>
        <span class="text-base-content/65 mt-0.5 block text-xs leading-relaxed">{@desc}</span>
      </span>
    </label>
    """
  end

  # A driver's published work for the day: the shared driver header and link actions, then each
  # trip as its own progress meter and stop spine. The link points at the driver's whole-day
  # /d/:token page, so it belongs to the driver rather than any single trip.
  attr :driver, :map, required: true
  attr :routes, :list, required: true

  defp published_driver_card(assigns) do
    ~H"""
    <article
      id={"driver-routes-#{@driver.id}"}
      class="admin-rise border-base-300/70 bg-base-200/40 rounded-xl border p-5"
    >
      <header class="mb-4 flex flex-wrap items-start justify-between gap-3">
        <div>
          <div class="flex flex-wrap items-center gap-2">
            <span :if={driver_active?(@routes)} aria-hidden="true" class="relative flex h-2 w-2">
              <span class="bg-primary/60 absolute inline-flex h-full w-full rounded-full motion-safe:animate-ping" />
              <span class="bg-primary relative inline-flex h-2 w-2 rounded-full" />
            </span>
            <h3 class="text-base font-semibold">{@driver.name}</h3>
          </div>
          <p class="text-base-content/65 mt-1 text-sm">{driver_summary(@routes)}</p>
        </div>

        <div class="flex flex-wrap gap-2">
          <button
            type="button"
            id={"copy-driver-#{@driver.id}"}
            phx-hook="CopyToClipboard"
            data-clipboard-text={driver_link(@driver)}
            data-copied-label={~t"Copied!"}
            class="btn btn-ghost btn-xs"
          >
            <.icon name="hero-link" class="h-4 w-4" />
            <span data-copy-label>{~t"Copy link"}</span>
          </button>
          <a
            href={~p"/d/#{@driver.link_token}"}
            target="_blank"
            rel="noopener"
            class="btn btn-ghost btn-xs"
          >
            <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" />
            {~t"Open driver view"}
          </a>
        </div>
      </header>

      <div class="space-y-4">
        <div :for={{route, index} <- Enum.with_index(@routes)}>
          <.return_to_store :if={index > 0} />
          <.published_trip route={route} number={index + 1} show_number={length(@routes) > 1} />
        </div>
      </div>
    </article>
    """
  end

  # One published trip within a driver's day: progress meter, the delivered/failed/remaining
  # tallies the monitor broadcasts patch, and the ordered stops drawn as a spine. The trip number
  # is shown only when the driver has more than one trip.
  attr :route, :map, required: true
  attr :number, :integer, required: true
  attr :show_number, :boolean, required: true

  defp published_trip(assigns) do
    ~H"""
    <div id={"route-monitor-#{@route.id}"}>
      <div class="mb-2 flex items-center justify-between gap-2">
        <span :if={@show_number} class="eyebrow text-base-content/65">{~t"Trip"} {@number}</span>
        <div class="ml-auto flex items-center gap-2">
          <span :if={route_complete?(@route)} class="badge badge-sm badge-success admin-badge-success">
            {~t"Completed"}
          </span>
          <button
            :if={route_cancellable?(@route)}
            type="button"
            id={"cancel-route-#{@route.id}"}
            phx-click="cancel_route"
            phx-value-id={@route.id}
            data-confirm={~t"Cancel this trip? Its orders will return to planning."}
            class="btn btn-ghost btn-xs text-error"
          >
            {~t"Cancel trip"}
          </button>
        </div>
      </div>

      <% progress = route_progress(@route) %>
      <% total = max(length(@route.route_stops), 1) %>
      <div class="bg-base-300/50 mb-3 flex h-1.5 w-full overflow-hidden rounded-full">
        <div class="bg-success h-full" style={"width:#{percent(progress.delivered, total)}%"} />
        <div class="bg-error h-full" style={"width:#{percent(progress.failed, total)}%"} />
      </div>

      <dl id={"route-progress-#{@route.id}"} class="mb-4 flex flex-wrap gap-x-5 gap-y-1 text-sm">
        <div id={"route-delivered-#{@route.id}"} class="flex items-baseline gap-1.5">
          <dd class="font-medium tabular-nums">{progress.delivered}</dd>
          <dt class="text-base-content/65">{~t"Delivered"}</dt>
        </div>
        <div id={"route-failed-#{@route.id}"} class="flex items-baseline gap-1.5">
          <dd class="font-medium tabular-nums">{progress.failed}</dd>
          <dt class="text-base-content/65">{~t"Failed"}</dt>
        </div>
        <div id={"route-remaining-#{@route.id}"} class="flex items-baseline gap-1.5">
          <dd class="font-medium tabular-nums">{progress.remaining}</dd>
          <dt class="text-base-content/65">{~t"Remaining"}</dt>
        </div>
      </dl>

      <ol class="border-base-300/70 relative ml-1.5 border-l">
        <li
          :for={stop <- @route.route_stops}
          id={"monitor-stop-#{stop.id}"}
          class="relative flex items-baseline justify-between gap-3 py-2.5 pl-6"
        >
          <span class="border-base-300 bg-base-100 text-base-content/65 absolute top-1.5 -left-3 flex h-6 w-6 items-center justify-center rounded-full border text-xs font-medium tabular-nums">
            {stop.sequence}
          </span>
          <span class="min-w-0">
            <span class="font-medium">{stop.recipient_name || stop.order_reference}</span>
            <span
              :if={stop.recipient_name}
              class="text-base-content/65 ml-2 text-sm tabular-nums"
            >
              {stop.order_reference}
            </span>
          </span>
          <span class="flex items-center gap-3 whitespace-nowrap text-sm">
            <span class={stop_status_class(stop.status)}>{stop_status_label(stop.status)}</span>
            <span class="text-base-content/65 tabular-nums">{format_distance(stop.leg_distance_m)}</span>
          </span>
        </li>
      </ol>
    </div>
    """
  end

  # The driver returns to the shop between trips to load the next run; the divider marks that
  # boundary so stacked trips don't read as one continuous route.
  defp return_to_store(assigns) do
    ~H"""
    <div class="text-base-content/50 mb-4 flex items-center gap-3">
      <span class="border-base-300/70 h-px flex-1 border-t border-dashed"></span>
      <span class="flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide">
        <.icon name="hero-arrow-uturn-left" class="h-4 w-4" />
        {~t"Return to store"}
      </span>
      <span class="border-base-300/70 h-px flex-1 border-t border-dashed"></span>
    </div>
    """
  end

  # A proposed (not yet published) route: an editable driver assignment, the run metrics,
  # and the ordered stops with their per-leg cost.
  attr :route, :map, required: true
  attr :drivers, :list, required: true
  attr :order_by_id, :map, required: true

  defp proposed_route_card(assigns) do
    ~H"""
    <article
      id={"proposed-route-#{@route.draft_id}"}
      class="admin-rise border-base-300/70 bg-base-100 rounded-xl border p-5"
    >
      <header class="mb-4 flex flex-wrap items-center justify-between gap-3">
        <form
          id={"route-driver-form-#{@route.draft_id}"}
          phx-change="assign_driver"
          class="flex items-center gap-2"
        >
          <input type="hidden" name="assignment[draft_id]" value={@route.draft_id} />
          <label for={"route-driver-#{@route.draft_id}"} class="eyebrow text-base-content/65">
            {~t"Driver"}
          </label>
          <select
            id={"route-driver-#{@route.draft_id}"}
            name="assignment[driver_id]"
            class="select select-sm font-medium"
          >
            <option
              :for={driver <- @drivers}
              value={driver.id}
              selected={driver.id == @route.driver_id}
            >
              {driver.name}
            </option>
          </select>
        </form>
        <dl class="flex flex-wrap items-baseline gap-x-5 gap-y-1 text-sm">
          <.route_stat label={~t"Stops"} value={length(@route.stops)} />
          <.route_stat label={~t"Distance"} value={format_distance(@route.total_distance_m)} />
          <.route_stat label={~t"Drive"} value={format_duration(@route.total_driving_s)} />
          <.route_stat label={~t"Total"} value={format_duration(@route.total_duration_s)} />
        </dl>
      </header>

      <ol class="border-base-300/70 relative ml-1.5 border-l">
        <li
          :for={stop <- @route.stops}
          class="relative flex items-baseline justify-between gap-3 py-2.5 pl-6"
        >
          <span class="border-base-300 bg-base-100 text-base-content/65 absolute top-1.5 -left-3 flex h-6 w-6 items-center justify-center rounded-full border text-xs font-medium tabular-nums">
            {stop.sequence}
          </span>
          <% order = @order_by_id[stop.stop_id] %>
          <% name = order_recipient_name(order) %>
          <span class="min-w-0">
            <span class="font-medium">{name || order_reference_or_id(order, stop.stop_id)}</span>
            <span :if={name} class="text-base-content/65 ml-2 text-sm tabular-nums">
              {order.order_reference}
            </span>
          </span>
          <span class="text-base-content/65 whitespace-nowrap text-sm tabular-nums">
            +{format_distance(stop.leg_from_previous.distance_m)} · +{format_duration(stop.leg_from_previous.duration_s)}
          </span>
        </li>
      </ol>
    </article>
    """
  end

  @impl true
  def handle_event("toggle_order", %{"id" => id}, socket) do
    {:noreply, socket |> update(:selected_order_ids, &toggle(&1, id)) |> discard_draft()}
  end

  def handle_event("toggle_all_orders", _params, socket) do
    selected_order_ids =
      if all_orders_selected?(socket.assigns) do
        MapSet.new()
      else
        MapSet.new(socket.assigns.eligible_orders, & &1.id)
      end

    {:noreply, socket |> assign(:selected_order_ids, selected_order_ids) |> discard_draft()}
  end

  def handle_event("toggle_driver", %{"id" => id}, socket) do
    {:noreply, socket |> update(:selected_driver_ids, &toggle(&1, id)) |> discard_draft()}
  end

  def handle_event("toggle_composer", _params, socket) do
    {:noreply, update(socket, :composer_collapsed?, &(not &1))}
  end

  def handle_event(
        "change_optimization",
        %{"optimization" => %{"strategy" => strategy}},
        socket
      )
      when strategy in ["cheapest", "balanced", "fastest"] do
    {:noreply,
     socket
     |> assign(:optimization_strategy, String.to_existing_atom(strategy))
     |> discard_draft()}
  end

  def handle_event(
        "assign_driver",
        %{
          "assignment" => %{
            "draft_id" => draft_id,
            "driver_id" => driver_id
          }
        },
        socket
      ) do
    if MapSet.member?(socket.assigns.selected_driver_ids, driver_id) do
      routes = assign_driver(socket.assigns.routes, draft_id, driver_id)
      {:noreply, assign(socket, :routes, routes)}
    else
      {:noreply, socket}
    end
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

  def handle_event("cancel_route", %{"id" => route_id}, socket) do
    case Enum.find(socket.assigns.published_routes, &(&1.id == route_id)) do
      nil ->
        {:noreply, socket}

      route ->
        case Route.cancel(route, actor: socket.assigns.current_user) do
          :ok ->
            {:noreply,
             socket
             |> load_planning_data()
             |> put_flash(:info, ~t"Trip cancelled. Its orders are available to plan again.")}

          {:error, _reason} ->
            {:noreply,
             put_flash(socket, :error, ~t"This trip can no longer be cancelled because delivery has started.")}
        end
    end
  end

  # The solve runs in handle_info, not the click handler, so the disabled button and
  # spinner render first — the optimizer call (a real HTTP round-trip in production) then
  # blocks this process until it returns.
  @impl true
  def handle_info(:run_optimize, socket) do
    case Solver.solve(build_problem(socket)) do
      {:ok, routes} ->
        {:noreply,
         assign(socket,
           optimizing?: false,
           routes: identify_draft_routes(routes),
           plan_error: nil,
           composer_collapsed?: true
         )}

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

  # Snapshot every physical item the driver needs to deliver; prices are deliberately excluded.
  defp product_lines(order) do
    order.line_items
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

    %{stops: stops, drivers: drivers, strategy: socket.assigns.optimization_strategy}
  end

  defp can_optimize?(assigns) do
    not assigns.optimizing? and MapSet.size(assigns.selected_order_ids) > 0 and
      MapSet.size(assigns.selected_driver_ids) > 0
  end

  defp all_orders_selected?(assigns) do
    MapSet.size(assigns.selected_order_ids) == length(assigns.eligible_orders)
  end

  # A draft describes one specific set of orders and drivers; once that set changes it no
  # longer applies, so clear it and let the florist re-optimize.
  defp discard_draft(socket), do: assign(socket, routes: nil, plan_error: nil)

  defp selected_drivers(assigns) do
    Enum.filter(assigns.drivers, &MapSet.member?(assigns.selected_driver_ids, &1.id))
  end

  defp order_recipient_name(nil), do: nil
  defp order_recipient_name(order), do: order.recipient_name || order.customer_name

  defp order_reference_or_id(nil, fallback), do: fallback
  defp order_reference_or_id(order, _fallback), do: order.order_reference

  defp strategy_label(:cheapest), do: ~t"Cheapest"
  defp strategy_label(:balanced), do: ~t"Balanced"
  defp strategy_label(:fastest), do: ~t"Fastest"

  defp percent(_count, 0), do: 0
  defp percent(count, total), do: round(count / total * 100)

  defp unused_drivers(assigns) do
    used = MapSet.new(assigns.routes || [], & &1.driver_id)

    assigns
    |> selected_drivers()
    |> Enum.reject(&MapSet.member?(used, &1.id))
  end

  defp identify_draft_routes(routes) do
    routes
    |> Enum.with_index()
    |> Enum.map(fn {route, draft_id} -> Map.put(route, :draft_id, Integer.to_string(draft_id)) end)
  end

  defp assign_driver(routes, draft_id, driver_id) do
    Enum.map(routes, fn route ->
      if route.draft_id == draft_id, do: %{route | driver_id: driver_id}, else: route
    end)
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

  # Group the day's published routes under their driver, keeping each driver's trips in publish
  # order (the rows arrive sorted by published_at). A driver picks up more than one trip when
  # they're included in several runs.
  defp routes_by_driver(routes) do
    routes
    |> Enum.group_by(& &1.driver_id)
    |> Enum.map(fn {_driver_id, [first | _] = driver_routes} -> {first.driver, driver_routes} end)
    |> Enum.sort_by(fn {driver, _routes} -> driver.name end)
  end

  defp driver_active?(routes), do: Enum.any?(routes, &(not route_complete?(&1)))

  defp driver_summary(routes) do
    total_stops = routes |> Enum.map(&length(&1.route_stops)) |> Enum.sum()

    case length(routes) do
      1 -> ~t"#{total_stops} stops"
      trips -> ~t"#{trips} trips · #{total_stops} stops"
    end
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

  defp route_cancellable?(route) do
    route.route_stops != [] and Enum.all?(route.route_stops, &(&1.status == :pending))
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

  defp format_distance(metres) do
    metres
    |> Kernel./(1000)
    |> :erlang.float_to_binary(decimals: 1)
    |> format_distance_value()
  end

  defp format_distance_km(kilometres), do: kilometres |> to_string() |> format_distance_value()

  defp format_distance_value(distance), do: ~t"#{distance} km"

  defp format_duration(seconds) do
    minutes = div(seconds, 60)

    cond do
      minutes >= 60 ->
        hours = div(minutes, 60)
        remaining_minutes = rem(minutes, 60)
        ~t"#{hours} h #{remaining_minutes} min"

      true ->
        ~t"#{minutes} min"
    end
  end

  defp toggle(set, id) do
    if MapSet.member?(set, id), do: MapSet.delete(set, id), else: MapSet.put(set, id)
  end
end
