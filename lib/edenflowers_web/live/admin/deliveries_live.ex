defmodule EdenflowersWeb.Admin.DeliveriesLive do
  @moduledoc """
  Daily delivery route planning and monitoring.

  Today's eligible orders are preselected; the florist picks active drivers, runs
  a synchronous HERE optimization, reviews an in-memory preview, and publishes.
  Publishing emails each driver their secret link and turns the page into a live
  progress view. Past dates render read-only history. Optimizing again for newly
  eligible orders appends supplemental trips to existing daily routes.
  """
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  require Ash.Query

  alias Edenflowers.{Dispatch, Format}
  alias Edenflowers.HereTourPlanning.Input
  alias Edenflowers.Store.{DeliveryRoute, Driver, Order}
  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.LiveUserAuth, :live_admin_required}

  @timezone "Europe/Helsinki"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, ~t"Deliveries")
     |> assign(:locale, Localize.get_locale())
     |> assign(:preview, nil)
     |> assign(:optimizing, false)
     |> assign(:publishing, false)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    date = parse_date(params["date"]) || today()
    {:noreply, load_for_date(socket, date)}
  end

  defp load_for_date(socket, date) do
    if connected?(socket) do
      Phoenix.PubSub.unsubscribe(Edenflowers.PubSub, "deliveries:#{socket.assigns[:date]}")
      Phoenix.PubSub.subscribe(Edenflowers.PubSub, "deliveries:#{date}")
    end

    eligible = list_eligible(date)
    drivers = Driver.list_active!(actor: actor(socket))
    routes = load_routes(date)
    assigned_driver_ids = MapSet.new(routes, & &1.driver_id)

    selected_orders = MapSet.new(eligible, & &1.id)

    selected_drivers =
      case Enum.reject(drivers, &MapSet.member?(assigned_driver_ids, &1.id)) do
        [single] -> MapSet.new([single.id])
        _ -> MapSet.new()
      end

    socket
    |> assign(:date, date)
    |> assign(:today?, date == today())
    |> assign(:past?, Date.compare(date, today()) == :lt)
    |> assign(:eligible_orders, eligible)
    |> assign(:drivers, drivers)
    |> assign(:routes, routes)
    |> assign(:selected_orders, selected_orders)
    |> assign(:selected_drivers, selected_drivers)
    |> assign(:preview, nil)
  end

  @impl true
  def handle_event("prev_day", _params, socket) do
    prev = Date.add(socket.assigns.date, -1) |> Date.to_iso8601()
    {:noreply, push_patch(socket, to: ~p"/admin/deliveries?date=#{prev}")}
  end

  def handle_event("next_day", _params, socket) do
    next = Date.add(socket.assigns.date, 1)

    if Date.compare(next, today()) == :gt do
      {:noreply, socket}
    else
      {:noreply, push_patch(socket, to: ~p"/admin/deliveries?date=#{Date.to_iso8601(next)}")}
    end
  end

  def handle_event("toggle_order", %{"id" => id}, socket) do
    {:noreply, socket |> toggle(:selected_orders, id) |> assign(:preview, nil)}
  end

  def handle_event("toggle_driver", %{"id" => id}, socket) do
    {:noreply, socket |> toggle(:selected_drivers, id) |> assign(:preview, nil)}
  end

  def handle_event("optimize", _params, socket) do
    with {:ok, input} <- build_input(socket) do
      send(self(), {:run_optimize, input})
      {:noreply, assign(socket, optimizing: true, preview: nil)}
    else
      {:error, message} -> {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("publish", _params, socket) do
    {:noreply, socket |> assign(:publishing, true) |> tap(fn _ -> send(self(), :run_publish) end)}
  end

  @impl true
  def handle_info({:run_optimize, input}, socket) do
    case adapter().optimize(input) do
      {:ok, plan} ->
        {:noreply, assign(socket, optimizing: false, preview: plan)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:optimizing, false)
         |> put_flash(:error, optimize_error_message(reason))}
    end
  end

  def handle_info(:run_publish, %{assigns: %{preview: nil}} = socket) do
    {:noreply, assign(socket, :publishing, false)}
  end

  def handle_info(:run_publish, socket) do
    attrs = %{
      delivery_date: socket.assigns.date,
      published_by_user_id: socket.assigns.current_user.id
    }

    case Dispatch.publish(socket.assigns.preview, attrs) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> assign(:publishing, false)
         |> put_flash(:info, ~t"Routes published and drivers emailed.")
         |> load_for_date(socket.assigns.date)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:publishing, false)
         |> put_flash(:error, publish_error_message(reason))}
    end
  end

  # Live progress: any publication or attempt on this date reloads the routes.
  def handle_info({:batch_published, _id}, socket) do
    {:noreply, load_for_date(socket, socket.assigns.date)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp build_input(socket) do
    orders =
      socket.assigns.eligible_orders
      |> Enum.filter(&MapSet.member?(socket.assigns.selected_orders, &1.id))

    driver_ids = MapSet.to_list(socket.assigns.selected_drivers)

    cond do
      orders == [] ->
        {:error, ~t"Select at least one order."}

      driver_ids == [] ->
        {:error, ~t"Select at least one driver."}

      length(driver_ids) > length(orders) ->
        {:error, ~t"There are more drivers than selected orders."}

      true ->
        {:ok,
         %Input{
           orders: Enum.map(orders, &order_coord/1),
           vehicle_ids: driver_ids,
           shop: Dispatch.shop_position(),
           date: socket.assigns.date
         }}
    end
  end

  defp order_coord(order) do
    [lat, lng] = order.position |> String.split(",") |> Enum.map(&String.to_float/1)
    %{id: order.id, lat: lat, lng: lng}
  end

  defp list_eligible(date) do
    Order.list_dispatch_eligible!(%{date: date}, actor: %{admin: true})
  end

  defp load_routes(date) do
    DeliveryRoute
    |> Ash.Query.filter(delivery_date == ^date)
    |> Ash.Query.load([
      :driver,
      trips: [stops: [order: [:order_reference, :recipient_name, :fulfillment_status, :payment_status]]]
    ])
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(actor: %{admin: true})
  end

  defp toggle(socket, key, id) do
    set = socket.assigns[key]
    set = if MapSet.member?(set, id), do: MapSet.delete(set, id), else: MapSet.put(set, id)
    assign(socket, key, set)
  end

  defp adapter, do: Application.get_env(:edenflowers, :here_tour_planning, Edenflowers.HereTourPlanning)

  defp actor(socket), do: socket.assigns.current_user

  defp today, do: DateTime.now!(@timezone) |> DateTime.to_date()

  defp parse_date(nil), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp optimize_error_message({:unassigned, _}),
    do: ~t"The optimizer could not assign every order. Adjust the selection and try again."

  defp optimize_error_message(_),
    do: ~t"Route optimization failed. Please try again."

  defp publish_error_message({:orders_already_assigned, _}),
    do: ~t"Some orders were already assigned to a route. The page has been refreshed."

  defp publish_error_message(_),
    do: ~t"Publishing failed. Please try again."

  # ------------------------------------------------------------------ render

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page width="wide">
        <.admin_page_header title={~t"Deliveries"}>
          <:subtitle>{Format.weekday_day_month(@date, @locale)}</:subtitle>
          <:actions>
            <div class="join">
              <button class="btn btn-sm join-item" phx-click="prev_day" aria-label={~t"Previous day"}>
                <.icon name="hero-chevron-left" class="h-4 w-4" />
              </button>
              <button
                class="btn btn-sm join-item"
                phx-click="next_day"
                disabled={@today?}
                aria-label={~t"Next day"}
              >
                <.icon name="hero-chevron-right" class="h-4 w-4" />
              </button>
            </div>
          </:actions>
        </.admin_page_header>

        <div class="space-y-6">
          <.planning_panel
            :if={@today? and @eligible_orders != []}
            eligible_orders={@eligible_orders}
            drivers={@drivers}
            selected_orders={@selected_orders}
            selected_drivers={@selected_drivers}
            optimizing={@optimizing}
            locale={@locale}
          />

          <.preview_panel
            :if={@preview}
            preview={@preview}
            drivers={@drivers}
            eligible_orders={@eligible_orders}
            publishing={@publishing}
            locale={@locale}
          />

          <.routes_panel routes={@routes} locale={@locale} />

          <p
            :if={@eligible_orders == [] and @routes == [] and @today?}
            class="text-base-content/60 text-sm"
          >
            {~t"No deliverable orders for today."}
          </p>
        </div>
      </.admin_page>
    </Layouts.admin>
    """
  end

  attr :eligible_orders, :list, required: true
  attr :drivers, :list, required: true
  attr :selected_orders, :any, required: true
  attr :selected_drivers, :any, required: true
  attr :optimizing, :boolean, required: true
  attr :locale, :string, required: true

  defp planning_panel(assigns) do
    ~H"""
    <section class="bg-base-100 border-base-300/70 rounded-lg border p-4 sm:p-5">
      <h2 class="text-base-content mb-4 text-base font-semibold">{~t"Plan a route"}</h2>

      <div class="grid gap-6 lg:grid-cols-2">
        <div>
          <h3 class="text-base-content/70 mb-2 text-xs font-semibold uppercase tracking-wide">
            {~t"Orders"}
          </h3>
          <ul class="space-y-1">
            <li :for={order <- @eligible_orders}>
              <label class="flex cursor-pointer items-start gap-3 rounded-md p-2 hover:bg-base-200/60">
                <input
                  type="checkbox"
                  class="checkbox checkbox-sm mt-0.5"
                  checked={MapSet.member?(@selected_orders, order.id)}
                  phx-click="toggle_order"
                  phx-value-id={order.id}
                />
                <span class="min-w-0">
                  <span class="block text-sm font-medium">
                    {order.order_reference} · {order.recipient_name || order.customer_name}
                  </span>
                  <span class="text-base-content/60 block text-xs">{order.delivery_address}</span>
                </span>
              </label>
            </li>
          </ul>
        </div>

        <div>
          <h3 class="text-base-content/70 mb-2 text-xs font-semibold uppercase tracking-wide">
            {~t"Drivers"}
          </h3>
          <p :if={@drivers == []} class="text-base-content/60 text-sm">
            {~t"No active drivers. Add one in AshAdmin first."}
          </p>
          <ul class="space-y-1">
            <li :for={driver <- @drivers}>
              <label class="flex cursor-pointer items-center gap-3 rounded-md p-2 hover:bg-base-200/60">
                <input
                  type="checkbox"
                  class="checkbox checkbox-sm"
                  checked={MapSet.member?(@selected_drivers, driver.id)}
                  phx-click="toggle_driver"
                  phx-value-id={driver.id}
                />
                <span class="text-sm font-medium">{driver.name}</span>
              </label>
            </li>
          </ul>
        </div>
      </div>

      <div class="mt-5">
        <button class="btn btn-primary btn-sm" phx-click="optimize" disabled={@optimizing}>
          <span :if={@optimizing} class="loading loading-spinner loading-xs"></span>
          {if @optimizing, do: ~t"Optimizing…", else: ~t"Optimize"}
        </button>
      </div>
    </section>
    """
  end

  attr :preview, :any, required: true
  attr :drivers, :list, required: true
  attr :eligible_orders, :list, required: true
  attr :publishing, :boolean, required: true
  attr :locale, :string, required: true

  defp preview_panel(assigns) do
    assigns =
      assigns
      |> assign(:driver_names, Map.new(assigns.drivers, &{&1.id, &1.name}))
      |> assign(:order_labels, Map.new(assigns.eligible_orders, &{&1.id, order_label(&1)}))

    ~H"""
    <section class="bg-base-100 border-primary/40 rounded-lg border p-4 sm:p-5">
      <h2 class="text-base-content mb-4 text-base font-semibold">{~t"Preview"}</h2>

      <div class="space-y-4">
        <div :for={assignment <- @preview.assignments} class="border-base-300/70 rounded-md border p-3">
          <div class="mb-2 flex items-center justify-between">
            <span class="text-sm font-semibold">
              {Map.get(@driver_names, assignment.vehicle_id, ~t"Driver")}
            </span>
            <span class="text-base-content/60 text-xs">
              {Format.km(assignment.total_distance)} · {Format.minutes(
                assignment.total_driving_duration + assignment.total_service_duration
              )}
            </span>
          </div>
          <ol class="space-y-1">
            <li :for={stop <- assignment.stops} class="flex items-center gap-2 text-sm">
              <span class="badge badge-sm badge-neutral">{stop.sequence}</span>
              <span>{Map.get(@order_labels, stop.order_id, stop.order_id)}</span>
              <span class="text-base-content/50 text-xs">
                {Format.km(stop.leg_distance)}
              </span>
            </li>
          </ol>
        </div>
      </div>

      <div class="mt-5">
        <button class="btn btn-primary btn-sm" phx-click="publish" disabled={@publishing}>
          <span :if={@publishing} class="loading loading-spinner loading-xs"></span>
          {~t"Publish and email drivers"}
        </button>
      </div>
    </section>
    """
  end

  attr :routes, :list, required: true
  attr :locale, :string, required: true

  defp routes_panel(assigns) do
    ~H"""
    <section :if={@routes != []} class="space-y-4">
      <h2 class="text-base-content text-base font-semibold">{~t"Published routes"}</h2>

      <div :for={route <- @routes} class="bg-base-100 border-base-300/70 rounded-lg border p-4 sm:p-5">
        <div class="mb-3 flex items-center justify-between">
          <span class="text-sm font-semibold">{route.driver.name}</span>
          <span class="text-base-content/60 text-xs">
            {route_progress_label(route)}
          </span>
        </div>

        <ol class="space-y-1">
          <%= for {stop, index} <- route_stops(route) |> Enum.with_index(1) do %>
            <li class="flex items-center gap-2 text-sm">
              <span class="badge badge-sm badge-neutral">{index}</span>
              <span class={[stop_done?(stop) && "text-base-content/50 line-through"]}>
                {stop.order.order_reference} · {stop.order.recipient_name}
              </span>
              <.stop_status_badge stop={stop} />
            </li>
          <% end %>
        </ol>
      </div>
    </section>
    """
  end

  attr :stop, :any, required: true

  defp stop_status_badge(assigns) do
    ~H"""
    <span class={["badge badge-xs", stop_badge_class(@stop)]}>{stop_status_label(@stop)}</span>
    """
  end

  defp route_stops(route) do
    route.trips
    |> Enum.sort_by(& &1.sequence)
    |> Enum.flat_map(fn trip -> Enum.sort_by(trip.stops, & &1.sequence) end)
  end

  defp route_progress_label(route) do
    stops = route_stops(route)
    done = Enum.count(stops, &stop_done?/1)
    Gettext.gettext(EdenflowersWeb.Gettext, "%{done} of %{total} delivered", done: done, total: length(stops))
  end

  defp stop_done?(stop), do: stop.order.fulfillment_status == :fulfilled

  defp stop_cancelled?(stop), do: stop.order.payment_status == :refunded

  defp stop_status_label(stop) do
    cond do
      stop_cancelled?(stop) -> ~t"Cancelled"
      stop_done?(stop) -> ~t"Delivered"
      true -> ~t"Pending"
    end
  end

  defp stop_badge_class(stop) do
    cond do
      stop_cancelled?(stop) -> "badge-warning"
      stop_done?(stop) -> "badge-success"
      true -> "badge-ghost"
    end
  end

  defp order_label(order), do: "#{order.order_reference} · #{order.recipient_name || order.customer_name}"
end
