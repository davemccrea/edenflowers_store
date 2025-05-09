defmodule EdenflowersWeb.CalendarComponent do
  use EdenflowersWeb, :live_component
  require Logger

  @week_begins :default
  @default_timezone "Europe/Helsinki"

  def mount(socket) do
    today_date = calculate_today()

    {:ok,
     socket
     |> assign(render_count: 0)
     |> assign(selected_date: nil)
     |> assign(week_begins: @week_begins)
     |> assign(today_date: today_date)
     |> assign(date_callback: Map.get(socket.assigns, :date_callback, fn _ -> :ok end))
     |> assign(on_select: fn date -> send(self(), {:date_selected, date}) end)
     |> update_calendar_view(today_date)}
  end

  def update(assigns, socket) do
    selected_date = assigns.selected_date
    today_date = socket.assigns.today_date
    view_date = if selected_date, do: selected_date, else: today_date

    # Only update the calendar view if the component is being rendered for the first time
    # TODO: is this even necessary?
    socket =
      if socket.assigns.render_count == 0,
        do: update_calendar_view(socket, view_date),
        else: socket

    {:ok,
     socket
     |> assign(assigns)
     |> assign(render_count: socket.assigns.render_count + 1)
     |> assign(selected_date: selected_date)}
  end

  attr :id, :string, required: true
  attr :field, :any, required: true
  attr :selected_date, :string, required: false
  attr :date_callback, :any, required: false
  attr :error, :boolean, default: false
  slot :day_decoration, required: false

  def render(assigns) do
    ~H"""
    <div
      id={"#{@id}"}
      class={"#{if @error, do: "border-error", else: "border-base-content/20"} bg-base-100 select-none rounded border p-2 sm:max-w-xs"}
      phx-hook="CalendarHook"
      data-view-date={@view_date}
      data-focusable-dates={get_focusable_dates_json(@view_date)}
    >
      <div class="flex items-center justify-between">
        <button
          id={"#{@id}-previous-month"}
          disabled={@view_date.month == @today_date.month}
          phx-target={@myself}
          phx-click="previous-month"
          type="button"
          class={previous_month_button_class(@view_date, @today_date)}
        >
          <span class="sr-only">{gettext("Previous month")}</span>
          <.icon name="hero-chevron-left" class="h-5 w-5" />
        </button>
        <button
          id={"#{@id}-current-month"}
          phx-target={@myself}
          phx-click="current-month"
          aria-label={gettext("Show current month")}
          type="button"
          class="cursor-pointer"
        >
          {Cldr.DateTime.to_string!(@view_date, format: "MMMM y")}
        </button>
        <button
          id={"#{@id}-next-month"}
          phx-target={@myself}
          phx-click="next-month"
          type="button"
          class="text-base-content flex flex-none cursor-pointer items-center justify-center p-1.5 hover:text-base-content/60"
        >
          <span class="sr-only">{gettext("Next month")}</span>
          <.icon name="hero-chevron-right" class="h-5 w-5" />
        </button>
      </div>

      <div class="border-base-content/10 mt-2 grid grid-cols-7 border-b text-center text-sm leading-6">
        <%= for week_day <- List.first(@week_rows) do %>
          <span>
            {Cldr.DateTime.to_string!(week_day, format: "EEEEEE")}
          </span>
        <% end %>
      </div>

      <div id={"#{@id}-grid"} role="grid" class="mt-1">
        <div :for={{week, _index} <- Enum.with_index(@week_rows)} role="row" class="grid grid-cols-7">
          <button
            :for={day <- week}
            id={"#{@id}-day-#{day}"}
            phx-target={@myself}
            phx-click="select"
            phx-value-date={day}
            data-key-arrow-up={calculate_date_for_key(day, "ArrowUp", @today_date)}
            data-key-arrow-down={calculate_date_for_key(day, "ArrowDown", @today_date)}
            data-key-arrow-left={calculate_date_for_key(day, "ArrowLeft", @today_date)}
            data-key-arrow-right={calculate_date_for_key(day, "ArrowRight", @today_date)}
            data-key-home={calculate_date_for_key(day, "Home", @today_date)}
            data-key-end={calculate_date_for_key(day, "End", @today_date)}
            data-key-page-up={calculate_date_for_key(day, "PageUp", @today_date)}
            data-key-page-down={calculate_date_for_key(day, "PageDown", @today_date)}
            type="button"
            aria-selected={
              if @selected_date,
                do: selected?(day, @selected_date),
                else: selected?(day, @view_date)
            }
            tabindex="-1"
            class={calendar_day_class(day, @view_date, @selected_date, @today_date, @date_callback.(day))}
          >
            <time datetime={day}>
              {Cldr.DateTime.to_string!(day, format: "d")}
            </time>
            {render_slot(@day_decoration, day)}
          </button>
        </div>
      </div>
    </div>
    """
  end

  # Event Handlers

  def handle_event("current-month", _, socket) do
    date = socket.assigns.today_date

    {:noreply, update_calendar_view(socket, date)}
  end

  def handle_event("previous-month", _, socket) do
    date =
      socket.assigns.view_date
      |> Cldr.Calendar.minus(:months, 1)

    {:noreply, update_calendar_view(socket, date)}
  end

  def handle_event("next-month", _, socket) do
    date =
      socket.assigns.view_date
      |> Cldr.Calendar.plus(:months, 1)

    {:noreply, update_calendar_view(socket, date)}
  end

  def handle_event("select", %{"date" => date_string}, socket) do
    with {:ok, date} <- Date.from_iso8601(date_string),
         true <- current_month?(date, socket.assigns.view_date),
         :ok <- socket.assigns.date_callback.(date) do
      socket.assigns.on_select.(date)

      {:noreply,
       socket
       |> assign(selected_date: date)
       |> update_calendar_view(date)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("keydown", %{"key" => key, "viewDate" => view_date}, socket) do
    date =
      view_date
      |> Date.from_iso8601!()
      |> handle_date_navigation(key, socket.assigns.today_date)

    {:noreply, update_calendar_view(socket, date)}
  end

  def handle_event("client-error", %{"message" => message}, socket) do
    Logger.error("Client error for #{socket.assigns.id} component: #{message}")
    {:noreply, socket}
  end

  # Helper Functions

  defp previous_month_button_class(view_date, today_date) do
    is_disabled = view_date.month == today_date.month
    base_class = "flex flex-none items-center justify-center p-1.5"

    if is_disabled do
      "#{base_class} text-gray-300 opacity-50"
    else
      "#{base_class} cursor-pointer text-base-content hover:text-base-content/60"
    end
  end

  defp calendar_day_class(day, view_date, selected_date, today_date, date_status) do
    is_current_month = current_month?(day, view_date)
    is_selected = selected?(day, selected_date)
    is_today = day == today_date
    is_disabled = date_status != :ok

    if !is_current_month do
      "opacity-0"
    else
      class_conditions = [
        {"relative aspect-square", true},
        {"underline", is_today},
        {"cursor-pointer", !is_disabled},
        {"bg-primary rounded-sm text-neutral-content hover:bg-primary/90", is_selected and !is_disabled},
        {"hover:bg-base-content/20 rounded-sm", !is_selected and !is_disabled},
        {"cursor-not-allowed text-base-content/20", is_disabled}
      ]

      class_conditions
      |> Enum.filter(fn {_class, condition} -> condition end)
      |> Enum.map(fn {class, _condition} -> class end)
      |> Enum.join(" ")
    end
  end

  defp update_calendar_view(socket, date) do
    socket
    |> assign(view_date: date)
    |> assign(week_rows: week_rows(date))
  end

  defp calculate_date_for_key(date, key, today_date), do: handle_date_navigation(date, key, today_date)

  defp handle_date_navigation(date, key, today_date) do
    target_date =
      case key do
        "ArrowUp" ->
          Date.add(date, -7)

        "ArrowDown" ->
          Date.add(date, 7)

        "ArrowLeft" ->
          Date.add(date, -1)

        "ArrowRight" ->
          Date.add(date, 1)

        "PageUp" ->
          Cldr.Calendar.plus(date, :months, 1)

        "PageDown" ->
          Cldr.Calendar.minus(date, :months, 1)

        "Home" ->
          Date.beginning_of_week(date, @week_begins)

        "End" ->
          Date.end_of_week(date, @week_begins)

        _ ->
          Logger.info("key #{key} not configured")
          date
      end

    disallow_past_months(target_date, date, today_date)
  end

  defp disallow_past_months(target_date, focused_date, today_date) do
    if Date.before?(target_date, Date.beginning_of_month(today_date)),
      do: focused_date,
      else: target_date
  end

  defp week_rows(view_date) do
    first =
      view_date
      |> Date.beginning_of_month()
      |> Date.beginning_of_week(@week_begins)

    last =
      view_date
      |> Date.end_of_month()
      |> Date.end_of_week(@week_begins)

    Date.range(first, last)
    |> Enum.map(& &1)
    |> Enum.chunk_every(7)
  end

  defp get_focusable_dates_json(view_date) do
    first = Date.beginning_of_month(view_date)
    last = Date.end_of_month(view_date)

    Date.range(first, last)
    |> Enum.map(&Calendar.strftime(&1, "%Y-%m-%d"))
    |> Jason.encode!()
  end

  defp selected?(day, selected_date), do: day == selected_date

  defp current_month?(day, view_date) do
    Date.beginning_of_month(day) == Date.beginning_of_month(view_date)
  end

  defp calculate_today(tz \\ @default_timezone) do
    tz
    |> DateTime.now!()
    |> DateTime.to_date()
  end
end
