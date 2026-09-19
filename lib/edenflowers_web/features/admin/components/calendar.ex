defmodule EdenflowersWeb.Admin.Calendar do
  @moduledoc """
  Admin wrapper around `EdenflowersWeb.DatePicker`.

  Holds every admin-specific binding — styling, override decoration,
  weekday-click — so the LiveView only orchestrates state. The inner
  component keeps its checkout-shaped contract; this module bridges to the
  admin view.
  """
  use EdenflowersWeb, :html

  import EdenflowersWeb.KeyDateIcon

  alias Edenflowers.Fulfillment.Availability
  alias EdenflowersWeb.Admin.CalendarViewModel

  # Shared "options disagree" tile — diagonal stripes via the calendar-mixed
  # @utility in app.css. Used by cells, the weekday header, and the legend.
  @mixed_tile_class "calendar-mixed"

  # Base box for the legend swatch — sized and positioned so the strike and
  # corner fragments can be reused unchanged. `shrink-0` stops the flex row from
  # compressing the square when the label wraps; `mt-0.5` aligns it to the first
  # text line (the row is `items-start`, not centred across wrapped lines).
  @swatch_base "relative inline-block w-4 h-4 mr-2 mt-0.5 shrink-0"

  attr :id, :string, required: true
  attr :scope, :any, required: true, doc: "`:all` or a FulfillmentOption id"
  attr :options, :list, required: true
  attr :today, :any, required: true, doc: "`Date.t()` — passed in so render stays pure"

  def grid(assigns) do
    ~H"""
    <.live_component
      id={@id}
      field={nil}
      module={EdenflowersWeb.DatePicker}
      selected_date={nil}
      cell_state={fn date -> CalendarViewModel.cell_state(@scope, @options, date, @today) end}
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
          weekday_class(CalendarViewModel.weekday_state(@scope, @options, weekday))
        end
      }
      on_week_click={:fulfillment_week_toggled}
      week_class={
        fn week ->
          week_class(CalendarViewModel.week_state(@scope, @options, week, @today))
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
  def legend(assigns) do
    ~H"""
    <aside class="text-sm md:max-w-xs md:pt-2">
      <h2 class="eyebrow text-base-content/70 mb-3">{~t"Legend"}</h2>
      <ul class="text-base-content/85 space-y-2 leading-snug">
        <li class="flex items-start">
          <span class={legend_swatch(:closed)}></span>
          <span>{~t"Unavailable to customers"}</span>
        </li>
        <li class="flex items-start">
          <span class={legend_swatch(:override)}></span>
          <span>{~t"Differs from the weekly schedule"}</span>
        </li>
        <li class="flex items-start">
          <span class={legend_swatch(:mixed)}></span>
          <span>{~t"Options have different settings"}</span>
        </li>
      </ul>
    </aside>
    """
  end

  # `:all` collapses to `false` — across options, "some override, some don't"
  # can't be summarized by a single corner mark.
  defp scope_override?(:all, _options, _date), do: false

  defp scope_override?(option_id, options, date) do
    case Enum.find(options, &(&1.id == option_id)) do
      nil -> false
      option -> Availability.override?(option, date)
    end
  end

  defp cell_class(_day, state, opts, override?) do
    today? = Keyword.get(opts, :today?, false)

    base = "relative aspect-square text-sm font-medium leading-none flex items-center justify-center"

    closed_class =
      "cursor-pointer bg-base-content/10 text-base-content/65 hover:bg-primary/10 calendar-strike-after hover:after:bg-error"

    state_class =
      case state do
        :open -> "cursor-pointer text-base-content/85 hover:bg-primary/10"
        :weekday_disabled -> closed_class
        :date_disabled -> closed_class
        :past -> "cursor-not-allowed text-base-content/60"
        :mixed -> "cursor-not-allowed text-base-content/85 #{@mixed_tile_class}"
      end

    today_class = if today?, do: " underline", else: ""
    override_class = if override?, do: " calendar-corner-before", else: ""

    "#{base} #{state_class}#{today_class}#{override_class}"
  end

  defp week_class(state) do
    base = "flex items-center justify-center text-base-content/70"

    case state do
      :all_past ->
        "#{base} cursor-not-allowed text-base-content/20"

      :all_closed ->
        # Click re-opens what's closed by override. Muted to signal that the
        # default direction is "open" — the opposite of every other state.
        "#{base} cursor-pointer text-base-content/65 hover:bg-primary/10 hover:text-base-content"

      _open_or_mixed ->
        "#{base} cursor-pointer hover:bg-primary/10 hover:text-base-content/85"
    end
  end

  defp weekday_class(state) do
    base = "relative px-1.5 py-1 text-xs font-semibold uppercase tracking-wider"

    state_class =
      case state do
        :on ->
          # On hover the text shifts from /65 → /85 so a "live" header signals
          # interactivity even before the background fills in.
          "cursor-pointer text-base-content/65 hover:text-base-content/85 hover:bg-primary/10"

        :off ->
          "cursor-pointer bg-base-content/10 text-base-content/65 hover:bg-primary/10 calendar-strike-after-tight hover:after:bg-error"

        :mixed ->
          "cursor-pointer text-base-content/85 hover:bg-primary/10 #{@mixed_tile_class}"
      end

    "#{base} #{state_class}"
  end

  # Uses the same calendar-strike-* / calendar-corner-* utilities as the
  # cells (defined in app.css), so the legend can't drift from the real cells.
  defp legend_swatch(:closed), do: "#{@swatch_base} bg-base-content/10 calendar-strike-after"
  defp legend_swatch(:override), do: "#{@swatch_base} ring-1 ring-inset ring-base-content/15 calendar-corner-before"
  defp legend_swatch(:mixed), do: "#{@swatch_base} #{@mixed_tile_class}"
end
