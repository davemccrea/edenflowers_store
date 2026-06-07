defmodule EdenflowersWeb.DriverRouteLive do
  use EdenflowersWeb, :live_view

  alias Edenflowers.Delivery.{Driver, Route, RouteStop}

  # Public, no-login page reached at /d/:token. The unguessable token is the only gate, so
  # reads and outcome writes run with authorize?: false once the token resolves a driver.
  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Driver.get_by_token(token) do
      {:ok, %Driver{} = driver} ->
        put_driver_locale(driver.locale)
        date = DateTime.now!("Europe/Helsinki") |> DateTime.to_date()
        routes = load_routes(driver, date)

        {:ok,
         socket
         |> assign(:page_title, driver.name)
         |> assign(:driver, driver)
         |> assign(:date, date)
         |> assign(:routes, routes)
         |> assign(:recording, nil)
         |> assign(:expanded_stop_ids, MapSet.new())
         |> assign(:directions_url, all_stops_directions_url(routes))}

      _ ->
        {:ok, assign(socket, driver: nil, routes: [], date: nil, recording: nil, page_title: ~t"Not found")}
    end
  end

  defp load_routes(driver, date), do: Route.list_for_driver!(driver.id, date, authorize?: false)

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
    <main id="main-content" tabindex="-1" class="mx-auto w-full max-w-xl px-4 py-6 outline-hidden sm:px-6 lg:px-8">
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

      <section :for={{route, index} <- Enum.with_index(@routes)} class="mb-8">
        <.return_to_store :if={index > 0} />
        <ol class="space-y-4">
          <.stop
            :for={stop <- route.route_stops}
            stop={stop}
            recording={@recording}
            expanded?={MapSet.member?(@expanded_stop_ids, stop.id)}
          />
        </ol>
      </section>
    </main>
    """
  end

  # Between trips: the driver drives back to the shop to load the next run before setting off
  # again, so the day's stops read as separate loops rather than one continuous list.
  defp return_to_store(assigns) do
    ~H"""
    <div class="text-base-content/50 mb-6 flex items-center gap-3">
      <span class="border-base-300/70 h-px flex-1 border-t border-dashed"></span>
      <span class="flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide">
        <.icon name="hero-arrow-uturn-left" class="h-4 w-4" />
        {~t"Return to store"}
      </span>
      <span class="border-base-300/70 h-px flex-1 border-t border-dashed"></span>
    </div>
    """
  end

  # A delivered stop collapses to a single confirmed line; everything else (pending or failed)
  # shows the full card with the record-outcome controls.
  attr :stop, :map, required: true
  attr :recording, :map, default: nil
  attr :expanded?, :boolean, default: false

  defp stop(%{stop: %{status: :delivered}} = assigns) do
    ~H"""
    <li class={["border-success/40 bg-success/5 rounded-lg border", @expanded? && "p-4"]}>
      <.completed_stop_header stop={@stop} expanded?={@expanded?} />
      <.stop_details :if={@expanded?} stop={@stop} />
    </li>
    """
  end

  defp stop(assigns) do
    ~H"""
    <li class={["rounded-lg border p-4", if(@stop.status == :failed, do: "border-error/50 bg-error/5", else: "border-base-300/70")]}>
      <.active_stop_header stop={@stop} />
      <.stop_details stop={@stop} />
      <.failed_stop_status :if={@stop.status == :failed} stop={@stop} />
      <.outcome_controls stop={@stop} recording={@recording} />
    </li>
    """
  end

  attr :stop, :map, required: true
  attr :expanded?, :boolean, required: true

  defp completed_stop_header(assigns) do
    ~H"""
    <button
      id={"completed-stop-toggle-#{@stop.id}"}
      type="button"
      phx-click="toggle_completed_stop"
      phx-value-stop={@stop.id}
      aria-expanded={to_string(@expanded?)}
      class={["flex w-full cursor-pointer items-baseline justify-between gap-3 text-left", @expanded? && "mb-3", not @expanded? && "p-4"]}
    >
      <span class="flex items-baseline gap-2">
        <.icon name="hero-check-circle" class="text-success h-4 w-4 self-center" />
        <span class="text-base-content/50 text-sm">{@stop.sequence}.</span>
        <span class="font-medium">{@stop.order_reference}</span>
      </span>
      <span class="text-base-content/65 whitespace-nowrap text-sm">{~t"Delivered"}</span>
    </button>
    """
  end

  attr :stop, :map, required: true

  defp active_stop_header(assigns) do
    ~H"""
    <div class="mb-3 flex items-baseline justify-between gap-3">
      <span class="flex items-baseline gap-2">
        <span class="text-base-content/50 text-sm">{@stop.sequence}.</span>
        <span class="font-medium">{@stop.order_reference}</span>
      </span>
      <span class="text-base-content/65 whitespace-nowrap text-sm">
        {format_distance(@stop.leg_distance_m)} · {format_duration(@stop.leg_duration_s)}
      </span>
    </div>
    """
  end

  attr :stop, :map, required: true

  defp failed_stop_status(assigns) do
    ~H"""
    <div class="text-error mt-4 flex items-center gap-2 text-sm font-medium">
      <.icon name="hero-x-circle" class="h-4 w-4" />
      <span>{~t"Couldn't deliver"}: {reason_label(@stop.failure_reason)}</span>
    </div>
    """
  end

  attr :stop, :map, required: true

  defp stop_details(assigns) do
    ~H"""
    <p :if={@stop.recipient_name} class="font-medium">{@stop.recipient_name}</p>

    <a :if={@stop.recipient_phone} href={"tel:#{@stop.recipient_phone}"} class="link text-sm">
      {@stop.recipient_phone}
    </a>

    <p :if={@stop.delivery_address} class="text-base-content/80 mt-2 whitespace-pre-line text-sm">
      {@stop.delivery_address}
    </p>

    <div :if={@stop.delivery_instructions} class="bg-base-200/60 mt-3 rounded-md p-3">
      <p class="text-base-content/50 text-xs font-medium uppercase tracking-wide">{~t"Instructions"}</p>
      <p class="whitespace-pre-line text-sm">{@stop.delivery_instructions}</p>
    </div>

    <div :if={@stop.card_message} class="border-base-300/70 mt-3 rounded-md border border-dashed p-3">
      <p class="text-base-content/50 text-xs font-medium uppercase tracking-wide">{~t"Card message"}</p>
      <p class="whitespace-pre-line text-sm">{@stop.card_message}</p>
    </div>

    <ul :if={@stop.products != []} class="text-base-content/80 mt-3 space-y-1 text-sm">
      <li :for={product <- @stop.products}>
        {product["quantity"]}× {product["name"]}
      </li>
    </ul>

    <a
      :if={@stop.position}
      href={"https://www.google.com/maps/dir/?api=1&destination=#{@stop.position}"}
      target="_blank"
      rel="noopener"
      class="btn btn-outline btn-sm mt-4 w-full"
    >
      <.icon name="hero-map-pin" class="h-4 w-4" />
      {~t"Directions"}
    </a>
    """
  end

  # The record-outcome area: two buttons until the driver picks delivered/failed, then the matching
  # form. A failed stop keeps the same controls so it can be retried (the new outcome overwrites).
  attr :stop, :map, required: true
  attr :recording, :map, default: nil

  defp outcome_controls(%{recording: %{stop_id: id}, stop: %{id: id}} = assigns) do
    ~H"""
    <form phx-submit="save_outcome" class="border-base-300/70 mt-4 space-y-3 border-t pt-4">
      <label class="block">
        <span class="text-base-content/65 text-sm">{outcome_prompt(@recording.kind)}</span>
        <select name="choice" required class="select select-bordered mt-1 w-full">
          <option value="" disabled selected>{~t"Choose one…"}</option>
          <option :for={{value, label} <- outcome_options(@recording.kind)} value={value}>{label}</option>
        </select>
      </label>

      <label class="block">
        <span class="text-base-content/65 text-sm">{~t"Note (required if you chose Other)"}</span>
        <textarea name="note" rows="2" class="textarea textarea-bordered mt-1 w-full"></textarea>
      </label>

      <p :if={@recording.error} class="text-error text-sm">{@recording.error}</p>

      <div class="flex gap-2">
        <button type="submit" class="btn btn-primary btn-sm flex-1">{~t"Save"}</button>
        <button type="button" phx-click="cancel_outcome" class="btn btn-ghost btn-sm">{~t"Cancel"}</button>
      </div>
    </form>
    """
  end

  defp outcome_controls(assigns) do
    ~H"""
    <div class="border-base-300/70 mt-4 flex gap-2 border-t pt-4">
      <button
        phx-click="start_outcome"
        phx-value-stop={@stop.id}
        phx-value-kind="delivered"
        class="btn btn-primary btn-sm flex-1"
      >
        {~t"Mark delivered"}
      </button>
      <button
        phx-click="start_outcome"
        phx-value-stop={@stop.id}
        phx-value-kind="failed"
        class="btn btn-outline btn-sm flex-1"
      >
        {~t"Couldn't deliver"}
      </button>
    </div>
    """
  end

  @impl true
  def handle_event("start_outcome", %{"stop" => stop_id, "kind" => kind}, socket) do
    {:noreply, assign(socket, :recording, %{stop_id: stop_id, kind: kind, error: nil})}
  end

  def handle_event("cancel_outcome", _params, socket) do
    {:noreply, assign(socket, :recording, nil)}
  end

  def handle_event("toggle_completed_stop", %{"stop" => stop_id}, socket) do
    expanded_stop_ids =
      if MapSet.member?(socket.assigns.expanded_stop_ids, stop_id) do
        MapSet.delete(socket.assigns.expanded_stop_ids, stop_id)
      else
        MapSet.put(socket.assigns.expanded_stop_ids, stop_id)
      end

    {:noreply, assign(socket, :expanded_stop_ids, expanded_stop_ids)}
  end

  def handle_event("save_outcome", %{"choice" => choice, "note" => note}, socket) do
    %{recording: recording, driver: driver, date: date} = socket.assigns
    stop = find_stop(socket.assigns.routes, recording.stop_id)
    note = String.trim(note)
    note = if note == "", do: nil, else: note

    result =
      case recording.kind do
        "delivered" ->
          RouteStop.record_delivered(stop, %{delivery_method: choice, outcome_note: note}, authorize?: false)

        "failed" ->
          RouteStop.record_failed(stop, %{failure_reason: choice, outcome_note: note}, authorize?: false)
      end

    case result do
      {:ok, _stop} ->
        {:noreply,
         socket
         |> assign(:routes, load_routes(driver, date))
         |> assign(:recording, nil)}

      {:error, _changeset} ->
        {:noreply, assign(socket, :recording, %{recording | error: ~t"Please add a note explaining the outcome."})}
    end
  end

  defp find_stop(routes, stop_id) do
    routes
    |> Enum.flat_map(& &1.route_stops)
    |> Enum.find(&(&1.id == stop_id))
  end

  defp outcome_prompt("delivered"), do: ~t"How was it delivered?"
  defp outcome_prompt("failed"), do: ~t"Why couldn't it be delivered?"

  defp outcome_options("delivered") do
    [
      {"handed_to_recipient", ~t"Handed to recipient"},
      {"left_in_safe_place", ~t"Left in a safe place"},
      {"other", ~t"Other"}
    ]
  end

  defp outcome_options("failed") do
    [
      {"recipient_unavailable", ~t"Recipient unavailable"},
      {"could_not_access", ~t"Couldn't access the property"},
      {"could_not_find", ~t"Couldn't find the address"},
      {"refused", ~t"Recipient refused"},
      {"other", ~t"Other"}
    ]
  end

  defp reason_label(:recipient_unavailable), do: ~t"Recipient unavailable"
  defp reason_label(:could_not_access), do: ~t"Couldn't access the property"
  defp reason_label(:could_not_find), do: ~t"Couldn't find the address"
  defp reason_label(:refused), do: ~t"Recipient refused"
  defp reason_label(:other), do: ~t"Other"
  defp reason_label(_), do: nil

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

  defp format_distance(metres) do
    distance = :erlang.float_to_binary(metres / 1000, decimals: 1)
    ~t"#{distance} km"
  end

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
end
