defmodule EdenflowersWeb.CalendarComponent do
  use EdenflowersWeb, :live_component
  require Logger

  alias EdenflowersWeb.CalendarComponent.Keymap

  @week_begins :default
  @default_timezone "Europe/Helsinki"

  def mount(socket) do
    today_date = calculate_today()

    {:ok,
     socket
     |> assign(selected_date: nil)
     |> assign(week_begins: @week_begins)
     |> assign(today_date: today_date)
     |> assign(cell_state: fn _ -> :open end)
     |> assign(cell_class: &default_cell_class/3)
     |> assign(clickable_states: [:open])
     |> assign(on_click: :date_selected)
     |> assign(on_weekday_click: nil)
     |> assign(weekday_class: &default_weekday_class/1)
     |> update_calendar_view(today_date)}
  end

  def update(assigns, socket) do
    selected_date = parse_date(assigns.selected_date)
    assigns = normalize_optional_assigns(assigns)

    socket =
      socket
      |> assign(assigns)
      |> assign(selected_date: selected_date)

    # If the parent passes a selected_date outside the current view month
    # (e.g. form pre-populated on remount), advance the view so the selected
    # pill is visible. No-op when the selected date is already in view.
    socket =
      if selected_date && not current_month?(selected_date, socket.assigns.view_date) do
        update_calendar_view(socket, selected_date)
      else
        socket
      end

    {:ok, socket}
  end

  attr :id, :string, required: true
  attr :field, :any, required: true
  attr :selected_date, :string, required: false

  attr :cell_state, :any,
    default: nil,
    doc:
      "(Date.t() -> :open | :past | :weekday_off | :override_off). " <>
        "Drives both clickability (only :open is clickable) and styling. " <>
        "Defaults to always-:open."

  attr :cell_class, :any,
    default: nil,
    doc:
      "Optional (Date.t(), cell_state, opts -> css_classes). Overrides default per-state styling. " <>
        "`opts` is a keyword list with `:selected?` and `:today?` so the override can compose with " <>
        "the standard selected/today affordances. Defaults to a single closed style for all non-:open states."

  attr :clickable_states, :any,
    default: nil,
    doc:
      "List of cell states that propagate a click. Defaults to `[:open]` (checkout's " <>
        "guarantee that only valid dates reach the parent). Admin editors typically pass " <>
        "`[:open, :weekday_off, :override_off]` so every cell can be toggled."

  attr :on_click, :any,
    default: :date_selected,
    doc:
      "Message tag (atom) sent to the parent as `{tag, date}` on a valid click. " <>
        "Defaults to `:date_selected` (the legacy checkout contract)."

  attr :on_weekday_click, :any,
    default: nil,
    doc:
      "Optional. When set, weekday headers become buttons and emit `{tag, weekday_atom}` (e.g. `:sunday`). " <>
        "When unset, headers remain static labels."

  attr :weekday_class, :any,
    default: nil,
    doc:
      "Optional (weekday_atom -> css_classes). Applied to each weekday header. Only meaningful when " <>
        "`on_weekday_click` is set. Defaults to a neutral button look."

  attr :error, :boolean, default: false
  slot :day_decoration, required: false

  def render(assigns) do
    ~H"""
    <div
      id={"#{@id}"}
      class={"#{if @error, do: "border-error", else: "border-base-content/20"} bg-base-100 select-none rounded border p-2"}
      phx-hook="CalendarHook"
      data-view-date={Date.to_iso8601(@view_date)}
      data-focusable-dates={get_focusable_dates_json(@view_date)}
    >
      <div role="status" aria-live="polite" aria-atomic="true" class="sr-only">
        {live_region_text(@view_date, @selected_date)}
      </div>

      <div class="flex items-center justify-between">
        <button
          id={"#{@id}-previous-month"}
          disabled={current_month?(@view_date, @today_date)}
          phx-target={@myself}
          phx-click="previous-month"
          type="button"
          class={previous_month_button_class(@view_date, @today_date)}
        >
          <span class="sr-only">{~t"Previous month"}</span>
          <.icon name="hero-chevron-left" class="h-5 w-5" />
        </button>
        <button
          id={"#{@id}-current-month"}
          phx-target={@myself}
          phx-click="current-month"
          type="button"
          class="cursor-pointer rounded-sm focus-visible:outline-base-content focus-visible:outline-2 focus-visible:outline-offset-2"
        >
          {Localize.DateTime.to_string!(@view_date, format: "MMMM y")}
          <span class="sr-only">— {~t"go to current month"}</span>
        </button>
        <button
          id={"#{@id}-next-month"}
          phx-target={@myself}
          phx-click="next-month"
          type="button"
          class="text-base-content flex flex-none cursor-pointer items-center justify-center rounded-sm p-1.5 hover:text-base-content/60 focus-visible:outline-base-content focus-visible:outline-2 focus-visible:outline-offset-2"
        >
          <span class="sr-only">{~t"Next month"}</span>
          <.icon name="hero-chevron-right" class="h-5 w-5" />
        </button>
      </div>

      <div
        aria-hidden={if @on_weekday_click, do: nil, else: "true"}
        class="border-base-content/20 mt-2 grid grid-cols-7 border-b text-center text-sm leading-6"
      >
        <%= for week_day <- List.first(@week_rows) do %>
          <%= if @on_weekday_click do %>
            <button
              type="button"
              phx-target={@myself}
              phx-click="weekday-click"
              phx-value-weekday={Atom.to_string(weekday_atom(week_day))}
              aria-label={weekday_aria_label(week_day)}
              class={@weekday_class.(weekday_atom(week_day))}
            >
              {Localize.DateTime.to_string!(week_day, format: "EEEEEE")}
            </button>
          <% else %>
            <span>
              {Localize.DateTime.to_string!(week_day, format: "EEEEEE")}
            </span>
          <% end %>
        <% end %>
      </div>

      <div id={"#{@id}-grid"} class="mt-1">
        <div :for={week <- @week_rows} class="grid grid-cols-7">
          <%= for day <- week do %>
            <%= if current_month?(day, @view_date) do %>
              <% state = @cell_state.(day) %>
              <% selectable? = state in @clickable_states %>
              <button
                id={"#{@id}-day-#{day}"}
                phx-target={@myself}
                phx-click="select"
                phx-value-date={day}
                data-key-targets={key_targets_json(day, @today_date)}
                type="button"
                aria-label={day_aria_label(day, @today_date, @selected_date, selectable?)}
                aria-pressed={if @selected_date && selected?(day, @selected_date), do: "true", else: "false"}
                aria-current={if day == @today_date, do: "date"}
                aria-disabled={if not selectable?, do: "true"}
                tabindex="-1"
                class={@cell_class.(day, state,
    selected?: selected?(day, @selected_date),
    today?: day == @today_date)}
              >
                <time datetime={Date.to_iso8601(day)} aria-hidden="true">
                  {Localize.DateTime.to_string!(day, format: "d")}
                </time>
                {render_slot(@day_decoration, day)}
              </button>
            <% else %>
              <div aria-hidden="true" class="aspect-square"></div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Event Handlers

  def handle_event("current-month", _, socket) do
    {:noreply, update_calendar_view(socket, socket.assigns.today_date)}
  end

  def handle_event("previous-month", _, socket) do
    {:noreply, update_calendar_view(socket, Date.shift(socket.assigns.view_date, month: -1))}
  end

  def handle_event("next-month", _, socket) do
    {:noreply, update_calendar_view(socket, Date.shift(socket.assigns.view_date, month: 1))}
  end

  def handle_event("select", %{"date" => date_string}, socket) do
    with {:ok, date} <- Date.from_iso8601(date_string),
         true <- current_month?(date, socket.assigns.view_date),
         true <- socket.assigns.cell_state.(date) in socket.assigns.clickable_states do
      send(self(), {socket.assigns.on_click, date})
      {:noreply, update_calendar_view(socket, date)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("weekday-click", %{"weekday" => weekday_string}, socket) do
    if tag = socket.assigns.on_weekday_click do
      send(self(), {tag, String.to_existing_atom(weekday_string)})
    end

    {:noreply, socket}
  end

  def handle_event("keydown", %{"key" => key, "viewDate" => view_date}, socket) do
    date =
      view_date
      |> Date.from_iso8601!()
      |> Keymap.next_date(key, socket.assigns.today_date)

    {:noreply, update_calendar_view(socket, date)}
  end

  def handle_event("client-error", %{"message" => message}, socket) do
    Logger.error("Client error for #{socket.assigns.id} component: #{message}")
    {:noreply, socket}
  end

  # Helper Functions

  defp previous_month_button_class(view_date, today_date) do
    is_disabled = current_month?(view_date, today_date)

    base_class =
      "focus-visible:outline-base-content flex flex-none items-center justify-center rounded-sm p-1.5 focus-visible:outline-2 focus-visible:outline-offset-2"

    if is_disabled do
      "#{base_class} text-base-content/20"
    else
      "#{base_class} cursor-pointer text-base-content hover:text-base-content/60"
    end
  end

  @doc false
  # Default per-state styling. All non-:open states collapse to a single closed style
  # so customers see one "unavailable" look. The admin editor passes its own `cell_class`
  # to distinguish weekday-off vs override-off vs past.
  def default_cell_class(_day, state, opts) do
    selected? = Keyword.get(opts, :selected?, false)
    today? = Keyword.get(opts, :today?, false)

    base = "relative aspect-square rounded-sm focus-visible:outline-2 focus-visible:outline-offset-2"

    state_class =
      cond do
        state != :open ->
          "cursor-not-allowed text-base-content/20 focus-visible:outline-base-content"

        selected? ->
          "cursor-pointer bg-primary text-primary-content hover:bg-primary/90 focus-visible:outline-base-content"

        true ->
          "cursor-pointer hover:bg-base-content/20 focus-visible:outline-base-content"
      end

    if today?, do: "#{base} #{state_class} underline", else: "#{base} #{state_class}"
  end

  defp normalize_optional_assigns(assigns) do
    assigns
    |> maybe_default(:cell_state, fn _ -> :open end)
    |> maybe_default(:cell_class, &default_cell_class/3)
    |> maybe_default(:on_click, :date_selected)
    |> maybe_default(:clickable_states, [:open])
    |> maybe_default(:weekday_class, &default_weekday_class/1)
  end

  @doc false
  def default_weekday_class(_weekday) do
    "hover:bg-base-content/10 focus-visible:outline-base-content cursor-pointer rounded-sm focus-visible:outline-2 focus-visible:outline-offset-2"
  end

  defp maybe_default(assigns, key, default) do
    case Map.get(assigns, key) do
      nil -> Map.put(assigns, key, default)
      _value -> assigns
    end
  end

  defp weekday_atom(date) do
    case Date.day_of_week(date) do
      1 -> :monday
      2 -> :tuesday
      3 -> :wednesday
      4 -> :thursday
      5 -> :friday
      6 -> :saturday
      7 -> :sunday
    end
  end

  defp weekday_aria_label(date) do
    full = Localize.DateTime.to_string!(date, format: "EEEE")
    ~t"Toggle " <> full
  end

  defp day_aria_label(day, today_date, selected_date, selectable?) do
    base = Localize.DateTime.to_string!(day, format: "EEEE, d MMMM y")

    suffixes =
      [
        if(day == today_date, do: ~t"today"),
        if(selected_date && selected?(day, selected_date), do: ~t"selected"),
        if(not selectable?, do: ~t"not available")
      ]
      |> Enum.reject(&is_nil/1)

    case suffixes do
      [] -> base
      list -> base <> ", " <> Enum.join(list, ", ")
    end
  end

  defp live_region_text(view_date, nil) do
    Localize.DateTime.to_string!(view_date, format: "MMMM y")
  end

  defp live_region_text(view_date, selected_date) do
    month = Localize.DateTime.to_string!(view_date, format: "MMMM y")
    date = Localize.DateTime.to_string!(selected_date, format: "EEEE, d MMMM y")
    "#{month}. #{date} #{~t"selected"}."
  end

  defp update_calendar_view(socket, date) do
    socket
    |> assign(view_date: date)
    |> assign(week_rows: week_rows(date))
  end

  @nav_keys ~w(ArrowUp ArrowDown ArrowLeft ArrowRight Home End PageUp PageDown)

  defp key_targets_json(date, today_date) do
    @nav_keys
    |> Map.new(fn key -> {key, Date.to_iso8601(Keymap.next_date(date, key, today_date))} end)
    |> Jason.encode!()
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
    |> Enum.map(&Date.to_iso8601/1)
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

  defp parse_date(%Date{} = date), do: date
  defp parse_date(str) when is_binary(str), do: Date.from_iso8601!(str)
  defp parse_date(_), do: nil
end
