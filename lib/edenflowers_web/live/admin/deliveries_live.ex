defmodule EdenflowersWeb.Admin.DeliveriesLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Format
  alias EdenflowersWeb.Layouts
  alias Edenflowers.Delivery.{Route, RouteStop}
  alias Edenflowers.Store.Order

  on_mount {EdenflowersWeb.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(_params, _session, socket) do
    today = DateTime.now!("Europe/Helsinki") |> DateTime.to_date()

    {:ok,
     socket
     |> assign(:page_title, ~t"Deliveries")
     |> assign(:date, today)
     |> assign(:subscribed_route_ids, MapSet.new())
     |> load_overview()}
  end

  defp load_overview(socket) do
    actor = socket.assigns.current_user
    published_routes = Route.list_published_for_date!(socket.assigns.date, actor: actor)
    eligible_orders = Order.list_eligible_for_delivery!(%{date: socket.assigns.date}, actor: actor)

    socket
    |> assign(:published_routes, published_routes)
    |> assign(:eligible_order_count, length(eligible_orders))
    |> subscribe_to_routes(published_routes)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page width="full">
        <.admin_page_header title={~t"Deliveries"}>
          <:subtitle>{~t"Monitor today's routes and prepare the next dispatch."}</:subtitle>
          <:actions>
            <.link
              :if={@eligible_order_count > 0}
              navigate={~p"/admin/deliveries/plan"}
              id="plan-dispatch"
              class="btn btn-primary btn-sm"
            >
              <.icon name="hero-plus" class="h-4 w-4" />
              {~t"Plan next dispatch"}
              <span class="badge badge-sm border-primary-content/20 bg-primary-content/15 text-primary-content">
                {@eligible_order_count}
              </span>
            </.link>
          </:actions>
        </.admin_page_header>

        <section :if={@published_routes != []} id="today-routes">
          <div class="border-base-300/70 mb-5 border-b pb-3">
            <p class="eyebrow text-primary mb-1">{~t"Live progress"}</p>
            <h2 class="text-base-content text-lg font-semibold tracking-tight">{~t"Today's routes"}</h2>
          </div>

          <div class="space-y-4">
            <.published_driver_card
              :for={{driver, routes} <- routes_by_driver(@published_routes)}
              driver={driver}
              routes={routes}
            />
          </div>
        </section>

        <div
          :if={@published_routes == []}
          class="border-base-300/70 bg-base-100 flex flex-col items-center gap-4 rounded-xl border border-dashed p-10 text-center"
        >
          <.icon name="hero-map" class="text-base-content/30 h-9 w-9" />
          <div>
            <h2 class="font-medium">{~t"No routes published today."}</h2>
            <p class="text-base-content/65 mt-1 text-sm">
              {if @eligible_order_count > 0,
                do: ~t"Plan a dispatch when the deliveries are ready to leave.",
                else: ~t"There are no eligible deliveries waiting to be assigned."}
            </p>
          </div>
          <.link
            :if={@eligible_order_count > 0}
            navigate={~p"/admin/deliveries/plan"}
            class="btn btn-primary btn-sm"
          >
            {~t"Plan next dispatch"}
          </.link>
        </div>
      </.admin_page>
    </Layouts.admin>
    """
  end

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
          <.published_route route={route} number={index + 1} show_number={length(@routes) > 1} />
        </div>
      </div>
    </article>
    """
  end

  attr :route, :map, required: true
  attr :number, :integer, required: true
  attr :show_number, :boolean, required: true

  defp published_route(assigns) do
    ~H"""
    <div id={"route-monitor-#{@route.id}"}>
      <div class="mb-2 flex items-center justify-between gap-2">
        <span :if={@show_number} class="eyebrow text-base-content/65">{~t"Route"} {@number}</span>
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
            data-confirm={~t"Cancel this route? Its orders will return to planning."}
            class="btn btn-ghost btn-xs text-error"
          >
            {~t"Cancel route"}
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
            <span :if={stop.recipient_name} class="text-base-content/65 ml-2 text-sm tabular-nums">
              {stop.order_reference}
            </span>
          </span>
          <span class="flex items-center gap-3 whitespace-nowrap text-sm">
            <span class={stop_status_class(stop.status)}>{stop_status_label(stop.status)}</span>
            <span class="text-base-content/65 tabular-nums">{Format.format_distance(stop.leg_distance_m)}</span>
          </span>
        </li>
      </ol>
    </div>
    """
  end

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

  @impl true
  def handle_event("cancel_route", %{"id" => route_id}, socket) do
    case Enum.find(socket.assigns.published_routes, &(&1.id == route_id)) do
      nil ->
        {:noreply, socket}

      route ->
        case Route.cancel(route, actor: socket.assigns.current_user) do
          :ok ->
            {:noreply,
             socket
             |> load_overview()
             |> put_flash(:info, ~t"Route cancelled. Its orders are available to plan again.")}

          {:error, _reason} ->
            {:noreply,
             put_flash(socket, :error, ~t"This route can no longer be cancelled because delivery has started.")}
        end
    end
  end

  @impl true
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
      route_count -> ~t"#{route_count} routes · #{total_stops} stops"
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

  defp percent(_count, 0), do: 0
  defp percent(count, total), do: round(count / total * 100)

  defp driver_link(driver), do: EdenflowersWeb.Endpoint.url() <> "/d/" <> driver.link_token

  defp stop_status_label(:pending), do: ~t"Pending"
  defp stop_status_label(:delivered), do: ~t"Delivered"
  defp stop_status_label(:failed), do: ~t"Failed"
  defp stop_status_label(:skipped), do: ~t"Skipped"

  defp stop_status_class(:pending), do: "badge badge-sm admin-badge-neutral"
  defp stop_status_class(:delivered), do: "badge badge-sm badge-success admin-badge-success"
  defp stop_status_class(:failed), do: "badge badge-sm badge-error"
  defp stop_status_class(:skipped), do: "badge badge-sm admin-badge-neutral"

end
