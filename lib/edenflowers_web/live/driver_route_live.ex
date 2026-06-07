defmodule EdenflowersWeb.DriverRouteLive do
  use EdenflowersWeb, :live_view

  alias Edenflowers.Delivery.{Driver, Route}

  # Public, no-login page reached at /d/:token. The unguessable token is the only gate, so
  # reads run with authorize?: false once the token resolves a driver. Read-only in this slice —
  # recording outcomes lands in slice 7.
  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Driver.get_by_token(token) do
      {:ok, %Driver{} = driver} ->
        put_driver_locale(driver.locale)
        date = DateTime.now!("Europe/Helsinki") |> DateTime.to_date()
        routes = Route.list_for_driver!(driver.id, date, authorize?: false)

        {:ok,
         socket
         |> assign(:page_title, driver.name)
         |> assign(:driver, driver)
         |> assign(:date, date)
         |> assign(:routes, routes)
         |> assign(:directions_url, all_stops_directions_url(routes))}

      _ ->
        {:ok, assign(socket, driver: nil, routes: [], date: nil, page_title: ~t"Not found")}
    end
  end

  # The driver page always renders in the driver's own preferred language, regardless of the
  # browser/session locale — mirrors Localize.Plug.put_locale_from_session, but from a known locale.
  defp put_driver_locale(locale) do
    Localize.put_locale(locale)

    case Localize.Locale.gettext_locale_id(locale, EdenflowersWeb.Gettext) do
      {:ok, gettext_locale} -> Gettext.put_locale(EdenflowersWeb.Gettext, gettext_locale)
      {:error, _} -> :ok
    end
  end

  @impl true
  def render(%{driver: nil} = assigns) do
    ~H"""
    <main id="main-content" tabindex="-1" class="flex min-h-screen items-center justify-center p-6 outline-hidden">
      <div class="text-center">
        <.icon name="hero-map" class="text-base-content/30 mx-auto h-10 w-10" />
        <p class="text-base-content/65 mt-3 text-sm">{~t"This delivery link isn't valid."}</p>
      </div>
    </main>
    """
  end

  def render(assigns) do
    ~H"""
    <main id="main-content" tabindex="-1" class="mx-auto max-w-xl px-4 py-6 outline-hidden">
      <header class="mb-6">
        <h1 class="text-xl font-semibold">{@driver.name}</h1>
        <p class="text-base-content/65 text-sm">{Edenflowers.Format.weekday_day_month(@date, @driver.locale)}</p>

        <a
          :if={@directions_url}
          href={@directions_url}
          target="_blank"
          rel="noopener"
          class="btn btn-primary btn-sm mt-4 w-full"
        >
          <.icon name="hero-map" class="h-4 w-4" />
          {~t"Open all stops in Google Maps"}
        </a>
      </header>

      <div
        :if={@routes == []}
        class="border-base-300/70 rounded-lg border border-dashed p-10 text-center"
      >
        <p class="text-base-content/65 text-sm">{~t"Nothing to deliver today."}</p>
      </div>

      <section :for={route <- @routes} class="mb-8">
        <div class="bg-base-200/60 mb-4 flex items-center gap-3 rounded-lg px-4 py-3">
          <.icon name="hero-building-storefront" class="text-base-content/60 h-5 w-5 shrink-0" />
          <span class="text-sm font-medium">{~t"Collect from shop"}</span>
        </div>

        <ol class="space-y-4">
          <li
            :for={stop <- route.route_stops}
            class="border-base-300/70 rounded-lg border p-4"
          >
            <div class="mb-3 flex items-baseline justify-between gap-3">
              <span class="flex items-baseline gap-2">
                <span class="text-base-content/50 text-sm">{stop.sequence}.</span>
                <span class="font-medium">{stop.order_reference}</span>
              </span>
              <span class="text-base-content/65 whitespace-nowrap text-sm">
                {format_km(stop.leg_distance_m)} km · {format_duration(stop.leg_duration_s)}
              </span>
            </div>

            <p :if={stop.recipient_name} class="font-medium">{stop.recipient_name}</p>

            <a
              :if={stop.recipient_phone}
              href={"tel:#{stop.recipient_phone}"}
              class="link text-sm"
            >
              {stop.recipient_phone}
            </a>

            <p :if={stop.delivery_address} class="text-base-content/80 mt-2 whitespace-pre-line text-sm">
              {stop.delivery_address}
            </p>

            <div :if={stop.delivery_instructions} class="bg-base-200/60 mt-3 rounded-md p-3">
              <p class="text-base-content/50 text-xs font-medium uppercase tracking-wide">{~t"Instructions"}</p>
              <p class="whitespace-pre-line text-sm">{stop.delivery_instructions}</p>
            </div>

            <div :if={stop.card_message} class="border-base-300/70 mt-3 rounded-md border border-dashed p-3">
              <p class="text-base-content/50 text-xs font-medium uppercase tracking-wide">{~t"Card message"}</p>
              <p class="whitespace-pre-line text-sm">{stop.card_message}</p>
            </div>

            <ul :if={stop.products != []} class="text-base-content/80 mt-3 space-y-1 text-sm">
              <li :for={product <- stop.products}>
                {product["quantity"]}× {product["name"]}
              </li>
            </ul>

            <a
              :if={stop.position}
              href={"https://www.google.com/maps/dir/?api=1&destination=#{stop.position}"}
              target="_blank"
              rel="noopener"
              class="btn btn-outline btn-sm mt-4 w-full"
            >
              <.icon name="hero-map-pin" class="h-4 w-4" />
              {~t"Directions"}
            </a>
          </li>
        </ol>
      </section>
    </main>
    """
  end

  # One directions link for the whole day: every stop across every route, in order, as Google
  # Maps waypoints with the last stop as the destination. Origin is omitted so it starts from the
  # driver's current location (the shop, when they set off). Returns nil if no stop has a position.
  defp all_stops_directions_url(routes) do
    positions =
      routes
      |> Enum.flat_map(& &1.route_stops)
      |> Enum.map(& &1.position)
      |> Enum.reject(&is_nil/1)

    case positions do
      [] ->
        nil

      _ ->
        {waypoints, [destination]} = Enum.split(positions, -1)
        url = "https://www.google.com/maps/dir/?api=1&travelmode=driving&destination=#{destination}"
        if waypoints == [], do: url, else: url <> "&waypoints=#{Enum.join(waypoints, "|")}"
    end
  end

  defp format_km(metres), do: :erlang.float_to_binary(metres / 1000, decimals: 1)

  defp format_duration(seconds) do
    minutes = div(seconds, 60)

    cond do
      minutes >= 60 -> "#{div(minutes, 60)}h #{rem(minutes, 60)}m"
      true -> "#{minutes}m"
    end
  end
end
