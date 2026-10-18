defmodule EdenflowersWeb.MonthGrid do
  @moduledoc """
  A month of days with month navigation and keyboard support. The caller
  draws each day, and optionally the weekday headers and a column before
  each week, through slots.

  The grid owns the month on screen: its month buttons and `CalendarHook`'s
  `"keydown"` and `"client-error"` events come back here. `CalendarHook` moves
  focus between the days with the arrow keys, as one Tab stop.

  Events from the caller's buttons have no `phx-target`, so they go to the
  LiveView, not to this component.

  ## Assigns

    * `:id` (required)
    * `:today` (required)
    * `:focus_date` - when it changes, the grid shows its month
    * `:status` - said after the month whenever the grid changes
    * `:class` - added to the root

  ## Slots

    * `:day` (required) - a day of the month on screen, given
      `%{date: Date.t(), attrs: keyword}`. Spread `attrs` on the day's button,
      as `CalendarHook` needs them: `<button {day.attrs}>`.
    * `:weekday` - a weekday header, given a date on that weekday. Without it,
      the headers are plain labels.
    * `:week` - a column before each week, given the week's seven dates.
    * `:footer` - below the grid, given the first of the month on screen.
  """
  use EdenflowersWeb, :live_component

  require Logger

  alias EdenflowersWeb.MonthGrid.Keymap

  @impl true
  def update(assigns, socket) do
    {focus_date, assigns} = Map.pop(assigns, :focus_date)

    socket =
      socket
      |> assign(status: nil, class: nil, weekday: [], week: [], footer: [])
      |> assign(assigns)
      |> assign_new(:view_date, fn %{today: today} -> focus_date || today end)

    socket =
      if focus_date && focus_date != socket.assigns[:focus_date],
        do: assign(socket, view_date: focus_date, focus_date: focus_date),
        else: assign(socket, focus_date: focus_date)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    month = Date.beginning_of_month(assigns.view_date)
    assigns = assign(assigns, month: month, weeks: weeks(month))

    ~H"""
    <div
      id={@id}
      class={["bg-base-100 select-none", @class]}
      phx-hook="CalendarHook"
      data-view-date={Date.to_iso8601(@view_date)}
      data-focusable-dates={focusable_dates_json(@month)}
    >
      <div role="status" aria-live="polite" aria-atomic="true" class="sr-only">
        {Localize.DateTime.to_string!(@month, format: "LLLL y")}{if @status, do: ". #{@status}"}
      </div>

      <div class="flex items-center justify-between">
        <button
          id={"#{@id}-previous-month"}
          type="button"
          phx-click="show-month"
          phx-target={@myself}
          phx-value-date={Date.shift(@view_date, month: -1)}
          disabled={@month == Date.beginning_of_month(@today)}
          class="size-11 text-base-content -ml-3 flex flex-none cursor-pointer items-center justify-center hover:text-base-content/60 disabled:text-base-content/20 disabled:cursor-default"
        >
          <span class="sr-only">{~t"Previous month"}</span>
          <.icon name="hero-chevron-left" class="h-5 w-5" />
        </button>
        <button
          id={"#{@id}-current-month"}
          type="button"
          phx-click="show-month"
          phx-target={@myself}
          phx-value-date={@today}
          class="min-h-11 px-3"
        >
          {Localize.DateTime.to_string!(@month, format: "LLLL y")}
          <span class="sr-only">, {~t"go to current month"}</span>
        </button>
        <button
          id={"#{@id}-next-month"}
          type="button"
          phx-click="show-month"
          phx-target={@myself}
          phx-value-date={Date.shift(@view_date, month: 1)}
          class="text-base-content size-11 -mr-3 flex flex-none items-center justify-center hover:text-base-content/60"
        >
          <span class="sr-only">{~t"Next month"}</span>
          <.icon name="hero-chevron-right" class="h-5 w-5" />
        </button>
      </div>

      <div
        aria-hidden={if @weekday == [], do: "true"}
        class={["border-base-content/20 mt-2 grid border-b text-center text-sm leading-6", columns(@week)]}
      >
        <span :if={@week != []} aria-hidden="true"></span>
        <%= for date <- List.first(@weeks) do %>
          <span :if={@weekday == []}>{Localize.DateTime.to_string!(date, format: "EEEEEE")}</span>
          {render_slot(@weekday, date)}
        <% end %>
      </div>

      <div id={"#{@id}-grid"} class="mt-1 flex flex-col gap-0.5">
        <div :for={week <- @weeks} class={["grid", columns(@week)]}>
          {render_slot(@week, week)}
          <%= for date <- week do %>
            <%= if Date.beginning_of_month(date) == @month do %>
              {render_slot(@day, %{date: date, attrs: day_attrs(@id, date, @today)})}
            <% else %>
              <div aria-hidden="true" class="aspect-square"></div>
            <% end %>
          <% end %>
        </div>
      </div>

      {render_slot(@footer, @month)}
    </div>
    """
  end

  @impl true
  def handle_event("show-month", %{"date" => date}, socket) do
    {:noreply, assign(socket, view_date: Date.from_iso8601!(date))}
  end

  def handle_event("keydown", %{"key" => key, "viewDate" => view_date}, socket) do
    date = view_date |> Date.from_iso8601!() |> Keymap.next_date(key, socket.assigns.today)
    {:noreply, assign(socket, view_date: date)}
  end

  def handle_event("client-error", %{"message" => message}, socket) do
    Logger.error("Client error on calendar #{socket.assigns.id}: #{message}")
    {:noreply, socket}
  end

  defp columns([] = _week_slot), do: "grid-cols-7 gap-0.5"
  defp columns(_week_slot), do: "grid-cols-[2rem_repeat(7,_1fr)] gap-0.5 sm:gap-x-1"

  defp day_attrs(id, date, today) do
    [id: "#{id}-day-#{date}", "data-key-targets": Keymap.targets_json(date, today), tabindex: "-1"]
  end

  defp weeks(month) do
    first = Date.beginning_of_week(month)
    last = month |> Date.end_of_month() |> Date.end_of_week()

    first |> Date.range(last) |> Enum.chunk_every(7)
  end

  # The dates the hook moves focus to without asking the server.
  defp focusable_dates_json(month) do
    month
    |> Date.range(Date.end_of_month(month))
    |> Enum.map(&Date.to_iso8601/1)
    |> Jason.encode!()
  end
end
