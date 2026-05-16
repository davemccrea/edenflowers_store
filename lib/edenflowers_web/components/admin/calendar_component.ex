defmodule EdenflowersWeb.Admin.CalendarComponent do
  @moduledoc """
  Admin wrapper around `EdenflowersWeb.CalendarComponent`.

  Holds every admin-specific binding — styling, override decoration,
  weekday-click — so the LiveView only orchestrates state. The inner
  component keeps its checkout-shaped contract; this module bridges to the
  admin view.
  """
  use EdenflowersWeb, :html

  alias Edenflowers.Store.{FulfillmentCalendar, KeyDates}

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
      cell_state={fn date -> FulfillmentCalendar.view_model(@scope, @options, date, @today).state end}
      cell_class={
        fn day, state, opts ->
          view = FulfillmentCalendar.view_model(@scope, @options, day, @today)
          cell_class(day, state, opts, view.override?)
        end
      }
      clickable_states={[:open, :weekday_off, :override_off]}
      on_click={:fulfillment_date_toggled}
      on_weekday_click={:fulfillment_weekday_toggled}
      weekday_class={
        fn weekday ->
          weekday_class(FulfillmentCalendar.weekday_state(@scope, @options, weekday))
        end
      }
    >
      <:day_decoration :let={day}>
        <.icon
          :if={icon = KeyDates.icon_for(day)}
          name={icon}
          class="text-error absolute right-0 bottom-0 left-0 m-auto h-3 w-3 -translate-y-0.5"
        />
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

  # Visual language: a florist's printed planner. Closed dates are crossed
  # out with a diagonal strike — the cell itself is marked as cancelled, not
  # just the digit. A muted gray background keeps closed cells visually
  # distinct from open ones. Cells whose state contradicts their weekday
  # rule (explicit overrides) carry a small sage triangle in the top-right.
  defp cell_class(_day, state, opts, override?) do
    today? = Keyword.get(opts, :today?, false)

    base =
      "relative aspect-square rounded text-sm font-medium leading-none flex items-center justify-center " <>
        "focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-base-content"

    # `after:` for the strike — the cell uses `before:` for the override
    # corner so the two pseudo-elements don't collide.
    closed_class =
      "cursor-pointer bg-base-content/10 text-base-content/65 hover:bg-base-content/15 hover:after:bg-error " <>
        diagonal_strike("after")

    state_class =
      case state do
        :open -> "cursor-pointer text-base-content hover:bg-primary/10"
        :weekday_off -> closed_class
        :override_off -> closed_class
        :past -> "cursor-not-allowed text-base-content/25"
        :mixed -> "cursor-not-allowed text-base-content/55 #{@mixed_tile_class}"
      end

    today_class = if today?, do: " font-bold text-primary", else: ""
    override_class = if override?, do: " " <> override_corner("before"), else: ""

    "#{base} #{state_class}#{today_class}#{override_class}"
  end

  defp weekday_class(state) do
    base =
      "rounded px-1.5 py-1 text-xs font-semibold uppercase tracking-wider " <>
        "focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-base-content"

    state_class =
      case state do
        :on ->
          "cursor-pointer text-base-content/65 hover:text-base-content hover:bg-primary/10"

        :off ->
          "cursor-pointer bg-base-content/10 text-base-content/65 line-through decoration-2 decoration-error/75 " <>
            "hover:bg-base-content/15 hover:decoration-error"

        :mixed ->
          "cursor-not-allowed text-base-content/45 #{@mixed_tile_class}"
      end

    "#{base} #{state_class}"
  end

  # The :closed swatch mirrors a closed cell in miniature, the :override swatch
  # mirrors a cell with a triangle corner. They reuse the same fragments as the
  # cell so the legend can't drift from the real thing.
  defp legend_swatch(:closed) do
    "#{@swatch_base} bg-base-content/10 #{diagonal_strike("before")}"
  end

  defp legend_swatch(:override) do
    "#{@swatch_base} ring-1 ring-inset ring-base-content/15 #{override_corner("after")}"
  end

  defp legend_swatch(:mixed) do
    "inline-block w-4 h-4 mr-2 rounded align-middle #{@mixed_tile_class}"
  end

  # Diagonal strike, ~22° off horizontal, ~56% of the container width.
  # Parameterized over `:before` vs `:after` because cells use the override
  # corner on `before:` already, while the legend swatch is free to use
  # `before:` for the strike itself.
  defp diagonal_strike(prefix) do
    "#{prefix}:absolute #{prefix}:left-[22%] #{prefix}:right-[22%] #{prefix}:top-1/2 #{prefix}:h-[2px] " <>
      "#{prefix}:-translate-y-1/2 #{prefix}:rotate-[-22deg] #{prefix}:bg-error/75 #{prefix}:content-[''] " <>
      "#{prefix}:rounded-full"
  end

  # Folded-page corner — small right-angled triangle in the top-right. Reads
  # as "marked by hand" without competing with the closed strike (centred) or
  # the today digit (centred).
  defp override_corner(prefix) do
    "#{prefix}:absolute #{prefix}:top-0 #{prefix}:right-0 #{prefix}:h-2 #{prefix}:w-2 " <>
      "#{prefix}:bg-primary/75 #{prefix}:content-[''] " <>
      "#{prefix}:[clip-path:polygon(100%_0,0_0,100%_100%)]"
  end
end
