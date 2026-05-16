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

  alias Edenflowers.Fulfillments
  alias Edenflowers.Store.FulfillmentCalendar

  # Shared swatch shape for the "options disagree" state. Used by cells, the
  # weekday header, and the legend, so they always read the same.
  @mixed_tile_class "bg-base-content/8 ring-1 ring-inset ring-base-content/15"

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
      cell_state={fn date -> scope_cell_state(@scope, @options, date, @today) end}
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
          weekday_class(FulfillmentCalendar.weekday_state(@scope, @options, weekday))
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
        <li class="flex items-center"><span class={legend_swatch(:closed)}></span> Closed</li>
        <li class="flex items-center">
          <span class={legend_swatch(:override)}></span> Override (contradicts weekday rule)
        </li>
        <li class="flex items-center"><span class={legend_swatch(:mixed)}></span> Mixed (options disagree)</li>
      </ul>
    </aside>
    """
  end

  defp scope_cell_state(:all, options, date, today) do
    FulfillmentCalendar.cell_state_for_options(options, date, today)
  end

  defp scope_cell_state(option_id, options, date, today) do
    case Enum.find(options, &(&1.id == option_id)) do
      nil -> :open
      option -> Fulfillments.admin_cell_state(option, date, today)
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
        :mixed -> "cursor-not-allowed text-base-content/65 #{@mixed_tile_class}"
      end

    today_class = if today?, do: " underline", else: ""
    override_class = if override?, do: " calendar-corner-before", else: ""

    "#{base} #{state_class}#{today_class}#{override_class}"
  end

  defp weekday_class(state) do
    base =
      "rounded px-1.5 py-1 text-xs font-semibold uppercase tracking-wider " <>
        "focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-base-content"

    state_class =
      case state do
        :on ->
          # On hover the text shifts from /65 → /85 so a "live" header signals
          # interactivity even before the background fills in.
          "cursor-pointer text-base-content/65 hover:text-base-content/85 hover:bg-primary/10"

        :off ->
          "cursor-pointer bg-base-content/10 text-base-content/65 line-through decoration-2 decoration-error/75 " <>
            "hover:bg-primary/10 hover:decoration-error"

        :mixed ->
          "cursor-not-allowed text-base-content/65 #{@mixed_tile_class}"
      end

    "#{base} #{state_class}"
  end

  # Uses the same calendar-strike-* / calendar-corner-* utilities as the
  # cells (defined in app.css), so the legend can't drift from the real cells.
  defp legend_swatch(:closed), do: "#{@swatch_base} bg-base-content/10 calendar-strike-before"
  defp legend_swatch(:override), do: "#{@swatch_base} ring-1 ring-inset ring-base-content/15 calendar-corner-after"
  defp legend_swatch(:mixed), do: "#{@swatch_base} #{@mixed_tile_class}"
end
