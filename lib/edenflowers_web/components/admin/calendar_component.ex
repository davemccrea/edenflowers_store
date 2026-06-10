defmodule EdenflowersWeb.Admin.CalendarComponent do
  @moduledoc """
  Admin wrapper around `EdenflowersWeb.CalendarComponent`.

  Holds every admin-specific binding — styling, override decoration,
  weekday-click — so the LiveView only orchestrates state. The inner
  component keeps its checkout-shaped contract; this module bridges to the
  admin view.
  """
  use EdenflowersWeb, :html

  import EdenflowersWeb.KeyDateIcon

  alias Edenflowers.Fulfillment.FulfillmentCalendar
  alias EdenflowersWeb.Admin.Calendar

  # Shared "options disagree" tile — diagonal stripes via the calendar-mixed
  # @utility in app.css. Used by cells, the weekday header, and the legend.
  @mixed_tile_class "calendar-mixed"

  # Base box for the legend swatch — sized and positioned so the strike and
  # corner fragments can be reused unchanged.
  @swatch_base "relative inline-block w-4 h-4 mr-2 rounded align-middle"

  attr :id, :string, required: true
  attr :scope, :any, required: true, doc: "`:all` or a FulfillmentOption id"
  attr :options, :list, required: true
  attr :today, :any, required: true, doc: "`Date.t()` — passed in so render stays pure"

  def admin_calendar(assigns) do
    ~H"""
    <.live_component
      id={@id}
      field={nil}
      module={EdenflowersWeb.CalendarComponent}
      selected_date={nil}
      cell_state={fn date -> Calendar.cell_state_for_scope(@scope, @options, date, @today) end}
      cell_class={
        fn day, state, opts ->
          cell_class(day, state, opts, scope_override?(@scope, @options, day))
        end
      }
      clickable_states={[:open, :weekday_disabled, :date_disabled]}
      on_click={:fulfillment_date_toggled}
      on_weekday_click={:fulfillment_weekday_toggled}
      weekday_class={
        fn weekday ->
          weekday_class(Calendar.weekday_state(@scope, @options, weekday))
        end
      }
      on_week_click={:fulfillment_week_toggled}
      week_class={
        fn week ->
          week_class(scope_week_state(@scope, @options, week, @today))
        end
      }
    >
      <:day_decoration :let={%{date: day, state: state}}>
        <.key_date_icon date={day} muted?={state == :past} />
      </:day_decoration>
    </.live_component>
    """
  end

  @doc """
  Static legend that matches the admin cell vocabulary. Kept next to the
  cell/weekday class functions so a change to either stays visible.
  """
  def admin_calendar_legend(assigns) do
    ~H"""
    <aside class="text-sm md:max-w-xs md:pt-2">
      <h2 class="eyebrow text-base-content/55 mb-3">Legend</h2>
      <ul class="text-base-content/85 space-y-2 leading-snug">
        <li class="flex items-center">
          <span class={legend_swatch(:closed)}></span>
          <span>Closed for bookings <span class="text-base-content/55">— not selectable by customers</span></span>
        </li>
        <li class="flex items-center">
          <span class={legend_swatch(:override)}></span>
          <span>Manually changed <span class="text-base-content/55">— your override on this date</span></span>
        </li>
        <li class="flex items-center">
          <span class={legend_swatch(:mixed)}></span>
          <span>Varies by option <span class="text-base-content/55">— switch to a single option to edit</span></span>
        </li>
      </ul>
    </aside>
    """
  end

  # Aggregate week state across the current scope. From the button's POV three
  # outcomes matter: everything open, everything closed, anything else (mixed),
  # or whole week in the past. Cross-option disagreement just folds into :mixed
  # — the bulk gesture is the gesture for that case.
  defp scope_week_state(scope, options, week, today) do
    case Calendar.scoped_options(scope, options) do
      [] ->
        :all_open

      list ->
        states = Enum.map(list, &Calendar.week_state(&1, week, today))

        cond do
          Enum.all?(states, &(&1 == :all_past)) -> :all_past
          Enum.all?(states, &(&1 == :all_open)) -> :all_open
          Enum.all?(states, &(&1 == :all_closed)) -> :all_closed
          true -> :mixed
        end
    end
  end

  # `:all` collapses to `false` — across options, "some override, some don't"
  # can't be summarized by a single corner mark.
  defp scope_override?(:all, _options, _date), do: false

  defp scope_override?(option_id, options, date) do
    case Enum.find(options, &(&1.id == option_id)) do
      nil -> false
      option -> FulfillmentCalendar.override?(option, date)
    end
  end

  defp cell_class(_day, state, opts, override?) do
    today? = Keyword.get(opts, :today?, false)

    base =
      "relative aspect-square rounded text-sm font-medium leading-none flex items-center justify-center " <>
        "focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-base-content"

    closed_class = "cursor-pointer bg-base-content/10 text-base-content/65 hover:bg-primary/10 calendar-strike-after"

    state_class =
      case state do
        :open -> "cursor-pointer text-base-content/85 hover:bg-primary/10"
        :weekday_disabled -> closed_class
        :date_disabled -> closed_class
        :past -> "cursor-not-allowed text-base-content/35"
        :mixed -> "cursor-not-allowed text-base-content/85 #{@mixed_tile_class}"
      end

    today_class = if today?, do: " underline", else: ""
    override_class = if override?, do: " calendar-corner-before", else: ""

    "#{base} #{state_class}#{today_class}#{override_class}"
  end

  defp week_class(state) do
    base =
      "flex items-center justify-center rounded text-base-content/55 " <>
        "focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-base-content"

    case state do
      :all_past ->
        "#{base} cursor-not-allowed text-base-content/20"

      :all_closed ->
        # Click re-opens what's closed by override. Muted to signal that the
        # default direction is "open" — the opposite of every other state.
        "#{base} cursor-pointer text-base-content/35 hover:bg-primary/10 hover:text-base-content/65"

      _open_or_mixed ->
        "#{base} cursor-pointer hover:bg-primary/10 hover:text-base-content/85"
    end
  end

  defp weekday_class(state) do
    base =
      "relative rounded px-1.5 py-1 text-xs font-semibold uppercase tracking-wider " <>
        "focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-base-content"

    state_class =
      case state do
        :on ->
          # On hover the text shifts from /65 → /85 so a "live" header signals
          # interactivity even before the background fills in.
          "cursor-pointer text-base-content/65 hover:text-base-content/85 hover:bg-primary/10"

        :off ->
          "cursor-pointer bg-base-content/10 text-base-content/65 hover:bg-primary/10 calendar-strike-after-tight"

        :mixed ->
          "cursor-pointer text-base-content/85 hover:bg-primary/10 #{@mixed_tile_class}"
      end

    "#{base} #{state_class}"
  end

  # Uses the same calendar-strike-* / calendar-corner-* utilities as the
  # cells (defined in app.css), so the legend can't drift from the real cells.
  defp legend_swatch(:closed), do: "#{@swatch_base} bg-base-content/10 calendar-strike-before"
  defp legend_swatch(:override), do: "#{@swatch_base} ring-1 ring-inset ring-base-content/15 calendar-corner-after"
  defp legend_swatch(:mixed), do: "#{@swatch_base} #{@mixed_tile_class}"
end
