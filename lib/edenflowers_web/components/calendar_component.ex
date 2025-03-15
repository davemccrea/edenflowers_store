defmodule EdenflowersWeb.CalendarComponent do
  use EdenflowersWeb, :live_component
  require Logger

  @week_begins :default
  @default_timezone "Europe/Helsinki"

  def mount(socket) do
    {:ok,
     socket
     |> assign(selected_date: nil)
     |> assign(week_begins: @week_begins)
     |> assign(allow_selection: Map.get(socket.assigns, :allow_selection, true))
     |> assign(event_callback: Map.get(socket.assigns, :event_callback, & &1))
     |> assign(date_callback: Map.get(socket.assigns, :date_callback, & &1))
     |> update_calendar_view(today())}
  end

  def update(assigns, socket) do
    selected_date = assigns.selected_date
    view_date = if selected_date, do: selected_date, else: today()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(selected_date: selected_date)
     |> update_calendar_view(view_date)}
  end

  attr :id, :string, required: true
  attr :hidden_input_id, :string, required: true
  attr :hidden_input_name, :string, required: true
  attr :selected_date, :string, required: false
  attr :allow_selection, :boolean, required: false
  attr :event_callback, :any, required: false
  attr :date_callback, :any, required: false
  slot :hidden_input, required: false
  slot :day_decoration, required: false

  def render(assigns) do
    ~H"""
    <div
      id={"#{@id}"}
      class="rounded border border-gray-400 p-2 shadow sm:max-w-xs"
      phx-hook="CalendarHook"
      data-view-date={@view_date}
      data-focusable-dates={get_focusable_dates_json(@view_date)}
    >
      <input type="hidden" id={@hidden_input_id} name={@hidden_input_name} value={@selected_date} />
      <div class="flex items-center justify-between">
        <button
          phx-target={@myself}
          phx-click="previous-month"
          type="button"
          class="flex flex-none items-center justify-center p-1.5 text-gray-400 hover:text-gray-500"
        >
          <span class="sr-only">{gettext("Previous month")}</span>
          <.icon name="hero-chevron-left" class="h-5 w-5" />
        </button>
        <button
          phx-target={@myself}
          phx-click="current-month"
          aria-label={gettext("Show current month")}
          type="button"
          class="font-medium"
        >
          {Cldr.DateTime.to_string!(@view_date, format: "MMMM y")}
        </button>
        <button
          phx-target={@myself}
          phx-click="next-month"
          type="button"
          class="flex flex-none items-center justify-center p-1.5 text-gray-400 hover:text-gray-500"
        >
          <span class="sr-only">{gettext("Next month")}</span>
          <.icon name="hero-chevron-right" class="h-5 w-5" />
        </button>
      </div>

      <div class="mt-2 grid grid-cols-7 border-b border-gray-200 text-center text-sm leading-6 text-gray-500">
        <%= for week_day <- List.first(@week_rows) do %>
          <span>
            {Cldr.DateTime.to_string!(week_day, format: "EEEEEE")}
          </span>
        <% end %>
      </div>

      <div role="grid" id={"#{@id}-grid"} class="mt-1 grid select-none grid-cols-7">
        <%= for {week, _index} <- Enum.with_index(@week_rows) do %>
          <%= for day <- week do %>
            <button
              phx-target={@myself}
              phx-click="select"
              phx-value-date={day}
              data-key-arrow-up={calculate_date_for_key(day, "ArrowUp")}
              data-key-arrow-down={calculate_date_for_key(day, "ArrowDown")}
              data-key-arrow-left={calculate_date_for_key(day, "ArrowLeft")}
              data-key-arrow-right={calculate_date_for_key(day, "ArrowRight")}
              data-key-home={calculate_date_for_key(day, "Home")}
              data-key-end={calculate_date_for_key(day, "End")}
              data-key-page-up={calculate_date_for_key(day, "PageUp")}
              data-key-page-down={calculate_date_for_key(day, "PageDown")}
              type="button"
              aria-selected={
                if @selected_date,
                  do: selected?(day, @selected_date),
                  else: selected?(day, @view_date)
              }
              tabindex="-1"
              class={calendar_day_class(day, @view_date, @selected_date, @date_callback.(day))}
            >
              <time datetime={day}>
                {Cldr.DateTime.to_string!(day, format: "d")}
              </time>
            </button>

            {render_slot(@day_decoration, day)}
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  defp calendar_day_class(day, view_date, selected_date, date_status) do
    if out_of_month?(day, view_date) do
      "opacity-0 cursor-default"
    else
      get_in_month_day_class(day, selected_date, date_status)
    end
  end

  defp out_of_month?(day, view_date) do
    previous_month?(day, view_date) || next_month?(day, view_date)
  end

  defp get_in_month_day_class(day, selected_date, date_status) do
    selected = selected?(day, selected_date)
    today = today?(day)
    disabled = date_status != :ok

    class_conditions = [
      {"underline", today},
      {"bg-blue-700 text-white hover:bg-blue-600", selected and not disabled},
      {"hover:bg-gray-100", not selected and not disabled},
      {"text-gray-300 cursor-not-allowed", disabled}
    ]

    class_conditions
    |> Enum.filter(fn {_class, condition} -> condition end)
    |> Enum.map(fn {class, _condition} -> class end)
    |> Enum.join(" ")
  end

  def handle_event("current-month", _, socket) do
    date = today()

    {:noreply,
     socket
     |> push_event("update-client", %{focus: false})
     |> update_calendar_view(date)}
  end

  def handle_event("previous-month", _, socket) do
    date =
      socket.assigns.view_date
      |> Cldr.Calendar.minus(:months, 1)

    {:noreply,
     socket
     |> push_event("update-client", %{focus: false})
     |> update_calendar_view(date)}
  end

  def handle_event("next-month", _, socket) do
    date =
      socket.assigns.view_date
      |> Cldr.Calendar.plus(:months, 1)

    {:noreply,
     socket
     |> push_event("update-client", %{focus: false})
     |> update_calendar_view(date)}
  end

  def handle_event("select", %{"date" => date}, socket) do
    date = Date.from_iso8601!(date)

    case socket.assigns.date_callback.(date) do
      :ok ->
        socket.assigns.event_callback.(date)
        selected_date = if socket.assigns.allow_selection, do: date, else: nil

        {:noreply,
         socket
         |> push_event("update-client", %{focus: true})
         |> assign(selected_date: selected_date)
         |> update_calendar_view(date)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("keydown", %{"key" => key, "currentDate" => view_date}, socket) do
    date =
      view_date
      |> Date.from_iso8601!()
      |> handle_date_navigation(key)

    {:noreply,
     socket
     |> push_event("update-client", %{focus: true})
     |> update_calendar_view(date)}
  end

  def handle_event("client-error", %{"message" => message}, socket) do
    Logger.error("Client error for #{socket.assigns.id} component: #{message}")
    {:noreply, socket}
  end

  defp calculate_date_for_key(date, key), do: handle_date_navigation(date, key)

  defp handle_date_navigation(date, key) do
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

  defp today?(day), do: day == today()

  defp current_month?(day, view_date) do
    Date.beginning_of_month(day) == Date.beginning_of_month(view_date)
  end

  defp previous_month?(day, view_date) do
    view_date
    |> Date.beginning_of_month()
    |> Cldr.Calendar.minus(:months, 1) == Date.beginning_of_month(day)
  end

  defp next_month?(day, view_date) do
    view_date
    |> Date.beginning_of_month()
    |> Cldr.Calendar.plus(:months, 1) == Date.beginning_of_month(day)
  end

  def today(tz \\ @default_timezone) do
    tz
    |> DateTime.now!()
    |> DateTime.to_date()
  end

  # Helper to update both view_date and week_rows together
  defp update_calendar_view(socket, date) do
    socket
    |> assign(view_date: date)
    |> assign(week_rows: week_rows(date))
  end
end
