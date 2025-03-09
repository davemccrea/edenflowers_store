defmodule EdenflowersWeb.CalendarComponent do
  use EdenflowersWeb, :live_component
  require Logger

  @week_begins :default

  def mount(socket) do
    current_date = today()
    date_callback = fn _date -> :ok end
    event_callback = fn _date -> Logger.warning("Event callback not set in CalendarComponent") end

    {:ok,
     socket
     |> assign(current_date: current_date)
     |> assign(selected_date: nil)
     |> assign(week_begins: @week_begins)
     |> assign(week_rows: week_rows(current_date))
     |> assign(allow_selection: Map.get(socket.assigns, :allow_selection, true))
     |> assign(event_callback: Map.get(socket.assigns, :event_callback, event_callback))
     |> assign(date_callback: Map.get(socket.assigns, :date_callback, date_callback))}
  end

  attr :id, :string, required: true
  attr :allow_selection, :boolean, required: false
  attr :event_callback, :any, required: false
  attr :date_callback, :any, required: false
  slot :day_decoration, required: false

  def render(assigns) do
    ~H"""
    <div id={@id} phx-hook="CalendarHook" data-current-date={@current_date} data-focusable-dates={focusable(@current_date)}>
      <div class="flex items-center justify-between">
        <button
          phx-target={@myself}
          phx-click="current-month"
          aria-label={gettext("Show current month")}
          type="button"
          class="text-sm text-gray-900"
        >
          {Cldr.DateTime.to_string!(@current_date, format: "MMMM y")}
        </button>
        <div class="flex items-center">
          <button
            phx-target={@myself}
            phx-click="previous-month"
            type="button"
            class="-my-1.5 flex flex-none items-center justify-center p-1.5 text-gray-400 hover:text-gray-500"
          >
            <span class="sr-only">{gettext("Previous month")}</span>
            <.icon name="hero-chevron-left" class="h-5 w-5" />
          </button>
          <button
            phx-target={@myself}
            phx-click="next-month"
            type="button"
            class="-my-1.5 -mr-1.5 ml-2 flex flex-none items-center justify-center p-1.5 text-gray-400 hover:text-gray-500"
          >
            <span class="sr-only">{gettext("Next month")}</span>
            <.icon name="hero-chevron-right" class="h-5 w-5" />
          </button>
        </div>
      </div>
      <div class="mt-10 grid grid-cols-7 text-center text-xs leading-6 text-gray-500">
        <%= for week_day <- List.first(@week_rows) do %>
          <span>
            {Cldr.DateTime.to_string!(week_day, format: "EEEEEE")}
          </span>
        <% end %>
      </div>
      <div role="grid" id={"#{@id}-grid"} class="mt-2 grid select-none grid-cols-7 text-sm">
        <%= for {week, index} <- Enum.with_index(@week_rows) do %>
          <%= for day <- week do %>
            <% disabled = @date_callback.(day) == :disabled %>
            <% past = @date_callback.(day) == :past %>
            <% disabled_or_past = disabled || past %>

            <div class={["relative py-2", index > 0 && "border-t border-gray-200"]}>
              <button
                phx-target={@myself}
                phx-click="select"
                phx-value-date={day}
                data-key-arrow-up={update_date(day, "ArrowUp")}
                data-key-arrow-down={update_date(day, "ArrowDown")}
                data-key-arrow-left={update_date(day, "ArrowLeft")}
                data-key-arrow-right={update_date(day, "ArrowRight")}
                data-key-home={update_date(day, "Home")}
                data-key-end={update_date(day, "End")}
                data-key-page-up={update_date(day, "PageUp")}
                data-key-page-down={update_date(day, "PageDown")}
                type="button"
                aria-selected={
                  if @selected_date,
                    do: selected?(day, @selected_date),
                    else: selected?(day, @current_date)
                }
                tabindex="-1"
                class={["mx-auto flex h-9 w-9 items-center justify-center rounded-full opacity-100", selected?(day, @selected_date) && "text-white", selected?(day, @selected_date) && today?(day) && "bg-blue-600", selected?(day, @selected_date) && not today?(day) && "bg-gray-900", selected?(day, @selected_date) || (today?(day) && "font-semibold"), not selected?(day, @selected_date) && not disabled_or_past && "hover:bg-gray-200", not selected?(day, @selected_date) && today?(day) && "text-blue-600", not selected?(day, @selected_date) && not today?(day) && current_month?(day, @current_date) && not disabled_or_past && "text-gray-900", ((not selected?(day, @selected_date) && not today?(day) && not current_month?(day, @current_date)) || disabled_or_past) && "text-gray-400", disabled_or_past && "cursor-default", disabled && "diagonal-strikethrough"]}
              >
                <time datetime={day}>
                  {Cldr.DateTime.to_string!(day, format: "d")}
                </time>
              </button>

              {render_slot(@day_decoration, day)}
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  def handle_event("current-month", _, socket) do
    date = today()

    {:noreply,
     socket
     |> push_event("update-client", %{focus: false})
     |> assign(current_date: date)
     |> assign(week_rows: week_rows(date))}
  end

  def handle_event("previous-month", _, socket) do
    date =
      socket.assigns.current_date
      |> Cldr.Calendar.minus(:months, 1)

    {:noreply,
     socket
     |> push_event("update-client", %{focus: false})
     |> assign(current_date: date)
     |> assign(week_rows: week_rows(date))}
  end

  def handle_event("next-month", _, socket) do
    date =
      socket.assigns.current_date
      |> Cldr.Calendar.plus(:months, 1)

    {:noreply,
     socket
     |> push_event("update-client", %{focus: false})
     |> assign(current_date: date)
     |> assign(week_rows: week_rows(date))}
  end

  def handle_event("select", %{"date" => date}, socket) do
    date = Date.from_iso8601!(date)

    case socket.assigns.date_callback.(date) == :ok do
      true ->
        socket.assigns.event_callback.(date)
        selected_date = if socket.assigns.allow_selection, do: date, else: nil

        {:noreply,
         socket
         |> push_event("update-client", %{focus: true})
         |> assign(selected_date: selected_date)
         |> assign(current_date: date)
         |> assign(week_rows: week_rows(date))}

      false ->
        {:noreply, socket}
    end
  end

  def handle_event("keydown", %{"key" => key, "currentDate" => current_date}, socket) do
    date =
      current_date
      |> Date.from_iso8601!()
      |> update_date(key)

    {:noreply,
     socket
     |> push_event("update-client", %{focus: true})
     |> assign(current_date: date)
     |> assign(week_rows: week_rows(date))}
  end

  def handle_event("error", %{"message" => message}, socket) do
    Logger.error("Client error for #{socket.assigns.id} component: #{message}")
    {:noreply, socket}
  end

  defp update_date(date, key) do
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

  defp week_rows(current_date) do
    first =
      current_date
      |> Date.beginning_of_month()
      |> Date.beginning_of_week(@week_begins)

    last =
      current_date
      |> Date.end_of_month()
      |> Date.end_of_week(@week_begins)

    Date.range(first, last)
    |> Enum.map(& &1)
    |> Enum.chunk_every(7)
  end

  defp focusable(current_date) do
    first = Date.beginning_of_month(current_date)
    last = Date.end_of_month(current_date)

    Date.range(first, last)
    |> Enum.map(&Calendar.strftime(&1, "%Y-%m-%d"))
    |> Jason.encode!()
  end

  defp selected?(day, selected_date), do: day == selected_date

  defp today?(day), do: day == today()

  defp current_month?(day, current_date),
    do: Date.beginning_of_month(day) == Date.beginning_of_month(current_date)

  def today(tz \\ "Europe/Helsinki") do
    tz
    |> DateTime.now!()
    |> DateTime.to_date()
  end
end
