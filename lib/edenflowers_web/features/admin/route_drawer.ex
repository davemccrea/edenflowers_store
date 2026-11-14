defmodule EdenflowersWeb.Admin.RouteDrawer do
  @moduledoc """
  The overview's delivery route drawer: Jennie ticks the day's deliveries,
  picks where she starts and finishes and when she leaves, and gets them in
  the fastest order from `Edenflowers.Fulfillment.plan_route`. Today's route
  can then start the day's Delivery run.
  """

  use EdenflowersWeb, {:html, gettext_domain: "admin"}

  import EdenflowersWeb.Admin.Components, only: [presence: 1]
  import EdenflowersWeb.Admin.Drawers, only: [admin_drawer: 1, drawer_body: 1, drawer_footer: 1]

  alias Edenflowers.Format

  # The order page's delivery map pin, as Mapbox takes it.
  @map_colour "e8542b"

  attr :date, Date, default: nil
  attr :orders, :list, required: true, doc: "the day's orders, from the overview"
  attr :form, Phoenix.HTML.Form, default: nil
  attr :places, :list, required: true, doc: "`Edenflowers.Fulfillment.route_places/0`"
  attr :route, :map, default: nil, doc: "what `plan_route` last returned"
  attr :route_stale?, :boolean, default: false, doc: "whether the form has changed since the route was planned"
  attr :run, :list, default: [], doc: "the stops of the day's Delivery run still to deliver"
  attr :map_token, :string, default: nil, doc: "Mapbox's, for the route's map; without it there is none"
  attr :locale, :any, required: true

  def route_drawer(assigns) do
    {stops, unplaced} =
      assigns.orders
      |> Enum.filter(&(&1.fulfillment_method == :delivery))
      |> Enum.split_with(& &1.position)

    late_ids =
      case assigns.route do
        %{error: {:missed_windows, orders}} -> Enum.map(orders, & &1.id)
        _ -> []
      end

    startable? =
      match?(%{error: nil}, assigns.route) and not assigns.route_stale? and
        assigns.date == Edenflowers.ShopTime.today()

    assigns = assign(assigns, stops: stops, unplaced: unplaced, late_ids: late_ids, startable?: startable?)

    ~H"""
    <.admin_drawer id="route-drawer" title={~t"Delivery route"} on_close={JS.push("close_route")}>
      <.form
        :if={@form}
        for={@form}
        id="route-form"
        phx-change="change_route"
        phx-submit="plan_route"
        class="flex min-h-0 flex-1 flex-col"
      >
        <.drawer_body>
          <p class="text-base-content/75 text-sm">{Format.weekday_day_month(@date, @locale)}</p>

          <div
            :if={@run != []}
            id="route-current-run"
            class="bg-warning/15 border-base-content/12 flex gap-2.5 border px-3 py-2.5 text-sm"
          >
            <.icon name="hero-truck" class="text-warning-content mt-0.5 h-4 w-4 shrink-0" />
            <p class="text-base-content">
              {dngettext(
                "admin",
                "Today's run has %{count} stop left, ticked below. Starting a new run replaces it.",
                "Today's run has %{count} stops left, ticked below. Starting a new run replaces it.",
                length(@run)
              )}
            </p>
          </div>

          <fieldset class="space-y-2">
            <legend class="text-base-content mb-2 text-sm font-semibold">{~t"Stops"}</legend>
            <input type="hidden" name={@form[:stops].name <> "[]"} value="" />
            <label :for={order <- @stops} class="flex cursor-pointer items-start gap-3 text-sm">
              <input
                type="checkbox"
                id={"route-stop-#{order.id}"}
                name={@form[:stops].name <> "[]"}
                value={order.id}
                checked={order.id in ticked(@form)}
                class="checkbox checkbox-sm checkbox-primary mt-0.5"
              />
              <span class="min-w-0">
                <span class="text-base-content block font-semibold">
                  {stop_name(order)}
                  <span :if={order.fulfillment_status != :ready} class="text-warning-content text-xs font-normal">
                    · {~t"Not ready"}
                  </span>
                  <span :if={order.id in @late_ids} class="text-error text-xs font-normal">
                    · {~t"Can't be reached in time"}
                  </span>
                </span>
                <span class="text-base-content/75 block">
                  {order.geocoded_address}
                  <span :if={Format.fulfillment_time_range(order, Format.locale())}>
                    · {Format.fulfillment_time_range(order, Format.locale())}
                  </span>
                </span>
              </span>
            </label>
            <p :if={@stops == []} class="text-base-content/75 text-sm">{~t"No deliveries to route."}</p>
          </fieldset>

          <div :if={@unplaced != []} id="route-unplaced" class="space-y-1">
            <h3 class="text-base-content text-sm font-semibold">{~t"Not on the route"}</h3>
            <p class="text-base-content/75 text-sm">{~t"These have no address HERE could find."}</p>
            <ul class="text-sm">
              <li :for={order <- @unplaced}>
                <.link navigate={~p"/admin/orders/#{order.id}"} class="link link-primary">{stop_name(order)}</.link>
              </li>
            </ul>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <.input
              :if={length(@places) > 1}
              field={@form[:start]}
              type="select"
              label={~t"Start"}
              options={place_options(@places)}
              class="select w-full"
            />
            <.input
              :if={length(@places) > 1}
              field={@form[:finish]}
              type="select"
              label={~t"End"}
              options={place_options(@places)}
              class="select w-full"
            />
            <%= if length(@places) == 1 do %>
              <input type="hidden" name={@form[:start].name} value={hd(@places)} />
              <input type="hidden" name={@form[:finish].name} value={hd(@places)} />
            <% end %>
            <.input field={@form[:departure]} type="time" label={~t"Leaving at"} required class="input w-full" />
          </div>

          <div :if={@route} id="route-result" class="border-base-content/12 space-y-3 border-t pt-4">
            <p
              :if={@route_stale?}
              id="route-stale"
              class="text-warning-content flex items-center gap-2 text-sm font-semibold"
            >
              <.icon name="hero-arrow-path" class="h-4 w-4 shrink-0" />
              {~t"Out of date. Plan again to see the new route."}
            </p>
            <div class={@route_stale? && "opacity-50"}>
              <.route_result route={@route} date={@date} map_token={@map_token} locale={@locale} />
            </div>
          </div>
        </.drawer_body>
        <.drawer_footer>
          <%= if @startable? do %>
            <.button id="start-delivery-run" type="button" variant="primary" phx-click="start_run">
              <.icon name="hero-truck" class="h-4 w-4" /> {~t"Start delivery run"}
            </.button>
            <.button type="submit" variant="secondary">{~t"Plan again"}</.button>
          <% else %>
            <.button type="submit" variant="primary" disabled={ticked(@form) == []}>
              <.icon name="hero-map" class="h-4 w-4" /> {~t"Plan route"}
            </.button>
          <% end %>
        </.drawer_footer>
      </.form>
    </.admin_drawer>
    """
  end

  attr :route, :map, required: true
  attr :date, Date, required: true
  attr :map_token, :string, default: nil
  attr :locale, :any, required: true

  defp route_result(%{route: %{error: nil}} = assigns) do
    assigns = assign(assigns, :map_url, assigns.map_token && route_map_url(assigns.route, assigns.map_token))

    ~H"""
    <section aria-labelledby="route-result-title" class="space-y-3">
      <div class="flex flex-wrap items-baseline justify-between gap-2">
        <h3 id="route-result-title" class="text-base-content text-sm font-semibold">{~t"Route"}</h3>
        <span class="text-base-content/75 text-sm tabular-nums">
          {Format.distance(@route.distance, @locale)} · {drive_time(@route.driving)}
        </span>
      </div>
      <%!-- The map covers the pulsing block once it loads. It hides while HERE plans again, and an id per map
           makes a new route's map a new element, so the block pulses until that one loads too. --%>
      <div :if={@map_url} id="route-map" class="border-base-content/12 aspect-[5/3] relative w-full border">
        <div class="bg-base-300 absolute inset-0 motion-safe:animate-pulse" aria-hidden="true"></div>
        <img
          id={"route-map-#{:erlang.phash2(@map_url)}"}
          src={@map_url}
          alt={~t"Map of the stops, numbered in driving order"}
          class="relative h-full w-full object-cover in-[.phx-submit-loading]:opacity-0"
        />
      </div>
      <ol class="divide-base-content/12 divide-y text-sm">
        <li :for={{stop, n} <- Enum.with_index(@route.stops, 1)} id={"route-#{n}"} class="flex gap-3 py-2">
          <span class="text-base-content/60 w-5 shrink-0 tabular-nums">{n}</span>
          <span class="min-w-0 flex-1">
            <.link navigate={~p"/admin/orders/#{stop.order.id}"} class="text-base-content block font-semibold">
              {stop_name(stop.order)}
            </.link>
            <span class="text-base-content/75 block">{stop.order.geocoded_address}</span>
          </span>
          <span class="shrink-0 text-right tabular-nums">
            {clock(stop.starts_at, @locale)}
            <span :if={stop.window} class="text-base-content/75 block text-xs">
              {Format.fulfillment_time_range(stop.order, Format.locale())}
            </span>
          </span>
        </li>
      </ol>
      <p class="text-base-content/75 text-sm">
        {~t"Back at #{time = clock(@route.back_at, @locale)}."}
      </p>
      <p :if={@date != Edenflowers.ShopTime.today()} class="text-base-content/75 text-sm">
        {~t"You can start the run on the day."}
      </p>
    </section>
    """
  end

  defp route_result(%{route: %{error: {:missed_windows, orders}}} = assigns) do
    assigns = assign(assigns, :orders, orders)

    ~H"""
    <div role="alert" class="text-error space-y-1 text-sm">
      <p>{~t"No route reaches every delivery in its agreed time. Untick one, or leave earlier:"}</p>
      <ul class="list-disc pl-5">
        <li :for={order <- @orders}>
          {stop_name(order)} · {Format.fulfillment_time_range(order, Format.locale())}
        </li>
      </ul>
    </div>
    """
  end

  defp route_result(%{route: %{error: :route_not_planned}} = assigns) do
    ~H"""
    <p role="alert" class="text-error text-sm">
      {~t"HERE couldn't plan the route. Try again in a moment."}
    </p>
    """
  end

  # Inputs the browser let through, like a cleared leaving time: trying again as they are won't help.
  defp route_result(assigns) do
    ~H"""
    <p role="alert" class="text-error text-sm">
      {~t"The route couldn't be planned. Check the stops and the leaving time."}
    </p>
    """
  end

  @doc """
  A Mapbox static map of a planned route: an unnumbered pin where it starts and ends, each stop numbered in
  driving order, and a straight line joining them in that order. HERE plans the order only, not the roads, so
  the line checks the order and the addresses rather than showing the drive.
  """
  def route_map_url(%{start: start, finish: finish, stops: stops}, token) do
    points = [start | Enum.map(stops, & &1.order.position)] ++ [finish]

    line =
      Jason.encode!(%{
        type: "Feature",
        properties: %{stroke: "#" <> @map_colour, "stroke-width": 3, "stroke-opacity": 0.6},
        geometry: %{type: "LineString", coordinates: Enum.map(points, &lng_lat/1)}
      })

    ends = [start, finish] |> Enum.uniq() |> Enum.map(&"pin-s+#{@map_colour}(#{Enum.join(lng_lat(&1), ",")})")

    stop_pins =
      for {stop, n} <- Enum.with_index(stops, 1),
          do: "pin-s-#{n}+#{@map_colour}(#{Enum.join(lng_lat(stop.order.position), ",")})"

    overlays = Enum.join(["geojson(#{URI.encode(line, &URI.char_unreserved?/1)})" | ends ++ stop_pins], ",")

    "https://api.mapbox.com/styles/v1/mapbox/streets-v12/static/#{overlays}/auto/1000x600@2x" <>
      "?padding=40&access_token=#{token}&logo=false&attribution=false"
  end

  # Positions are stored "latitude,longitude"; Mapbox wants longitude first.
  defp lng_lat(position) do
    [lat, lng] = for part <- String.split(position, ","), do: part |> String.trim() |> Float.parse() |> elem(0)
    [lng, lat]
  end

  @doc """
  The form's starting values for a day, from and to the shop. With a Delivery
  run on, its stops still to deliver are ticked, so planning again starts from
  it. Otherwise the routable deliveries marked Ready are, as those are the
  ones made. She can still tick any other.
  """
  def form(orders, date, run) do
    stops =
      if run != [],
        do: Enum.map(run, & &1.id),
        else: for(%{fulfillment_method: :delivery, fulfillment_status: :ready, position: p} = o <- orders, p, do: o.id)

    to_form(
      %{
        "stops" => stops,
        "start" => "shop",
        "finish" => "shop",
        "departure" => default_departure(date)
      },
      as: :route
    )
  end

  defp default_departure(date) do
    now = Edenflowers.ShopTime.now()

    if date == DateTime.to_date(now), do: Calendar.strftime(now, "%H:%M"), else: "09:00"
  end

  @doc "The ids of the stops ticked in the form, without the empty value that lets none be sent."
  def ticked(form), do: Enum.reject(form[:stops].value || [], &(&1 == ""))

  defp place_options(places), do: Enum.map(places, &{place_label(&1), &1})

  defp place_label(:shop), do: ~t"Shop"
  defp place_label(:home), do: ~t"Home"

  @doc "Who a stop is for: a gift's recipient, otherwise the customer."
  def stop_name(order) do
    if order.gift && presence(order.recipient_name),
      do: order.recipient_name,
      else: order.customer_name || ~t"Unnamed customer"
  end

  defp clock(datetime, locale), do: Format.time(DateTime.to_time(datetime), locale)

  defp drive_time(seconds) do
    minutes = div(seconds + 59, 60)

    if minutes < 60,
      do: ~t"#{minutes} min",
      else: ~t"#{hours = div(minutes, 60)} h #{minutes = rem(minutes, 60)} min"
  end
end
