defmodule EdenflowersWeb.Admin.Calendar do
  @moduledoc """
  Admin wrapper around `EdenflowersWeb.DatePicker` for the shop calendar.

  Holds every admin-specific binding — styling, override decoration,
  weekday-click — so the LiveView only orchestrates state. The inner
  component keeps its checkout-shaped contract; this module bridges to the
  admin view.
  """
  use EdenflowersWeb, :html

  import EdenflowersWeb.KeyDateIcon

  alias Edenflowers.Fulfillment.Availability
  alias Edenflowers.Fulfillment.KeyDates

  @swatch_base "relative inline-block w-4 h-4 mr-2 mt-0.5 shrink-0"

  attr :id, :string, required: true
  attr :calendar, :any, required: true, doc: "`ShopCalendar.t()`"
  attr :today, :any, required: true, doc: "`Date.t()` — passed in so render stays pure"

  def grid(assigns) do
    ~H"""
    <.live_component
      id={@id}
      field={nil}
      module={EdenflowersWeb.DatePicker}
      selected_date={nil}
      framed={false}
      cell_state={fn date -> Availability.admin_cell_state(@calendar, date, @today) end}
      cell_class={fn day, state, opts -> cell_class(state, opts, Availability.override?(@calendar, day)) end}
      clickable_states={[:open, :weekday_disabled, :date_disabled]}
      state_label={&cell_state_label/1}
      weekday_state_label={fn weekday -> weekday_state_label(weekday in @calendar.available_days) end}
      on_click={:fulfillment_date_toggled}
      on_weekday_click={:fulfillment_weekday_toggled}
      weekday_class={fn weekday -> weekday_class(weekday in @calendar.available_days) end}
      on_week_click={:fulfillment_week_toggled}
      week_class={fn week -> week_class(week_toggle_direction(@calendar, week, @today)) end}
    >
      <:day_decoration :let={%{date: day, state: state, selected?: selected?}}>
        <.key_date_icon date={day} selected?={selected?} muted?={state == :past} />
      </:day_decoration>
      <:footer :let={%{view_date: month}}>
        <.key_date_caption month={month} />
      </:footer>
    </.live_component>
    """
  end

  @doc """
  What the week's toggle does: `:closed` while any of its non-past, non-key
  dates is open, `:open` once all are closed, and `nil` when none is left to
  change. Key dates are skipped, as `SetWeek` skips them.
  """
  def week_toggle_direction(calendar, week, today) do
    states =
      for date <- week, Date.compare(date, today) != :lt, not KeyDates.key_date?(date) do
        Availability.admin_cell_state(calendar, date, today)
      end

    cond do
      states == [] -> nil
      :open in states -> :closed
      true -> :open
    end
  end

  @doc """
  Static legend that matches the admin cell vocabulary. Kept next to the
  cell/weekday class functions so a change to either stays visible.
  """
  def legend(assigns) do
    ~H"""
    <aside class="text-sm md:max-w-xs md:pt-2">
      <h2 class="eyebrow text-base-content/65 mb-3">{~t"Legend"}</h2>
      <ul class="text-base-content/85 space-y-2 leading-snug">
        <li class="flex items-start">
          <span class={legend_swatch(:closed)}></span>
          <span>{~t"Closed"}</span>
        </li>
        <li class="flex items-start">
          <span class={legend_swatch(:override)}></span>
          <span>{~t"Differs from the weekly schedule"}</span>
        </li>
      </ul>
    </aside>
    """
  end

  defp cell_state_label(:open), do: ~t"open"
  defp cell_state_label(:weekday_disabled), do: ~t"closed"
  defp cell_state_label(:date_disabled), do: ~t"closed"
  defp cell_state_label(:past), do: ~t"past"

  defp weekday_state_label(true = _open?), do: ~t"open"
  defp weekday_state_label(false = _open?), do: ~t"closed"

  defp cell_class(state, opts, override?) do
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
      end

    today_class = if today?, do: " underline", else: ""
    override_class = if override?, do: " calendar-corner-before", else: ""

    "#{base} #{state_class}#{today_class}#{override_class}"
  end

  defp week_class(direction) do
    base = "flex items-center justify-center text-base-content/70"

    case direction do
      nil ->
        "#{base} cursor-not-allowed text-base-content/20"

      :open ->
        # Click re-opens what's closed by override. Muted to signal that the
        # default direction is "open" — the opposite of every other state.
        "#{base} cursor-pointer text-base-content/65 hover:bg-primary/10 hover:text-base-content"

      :closed ->
        "#{base} cursor-pointer hover:bg-primary/10 hover:text-base-content/85"
    end
  end

  defp weekday_class(open?) do
    base = "relative px-1.5 py-3.5 sm:py-1 text-xs font-semibold uppercase tracking-wider"

    state_class =
      if open? do
        "cursor-pointer text-base-content/65 hover:text-base-content/85 hover:bg-primary/10"
      else
        "cursor-pointer bg-base-content/10 text-base-content/65 hover:bg-primary/10 calendar-strike-after-tight hover:after:bg-error"
      end

    "#{base} #{state_class}"
  end

  # Uses the same calendar-strike-* / calendar-corner-* utilities as the
  # cells (defined in admin.css), so the legend can't drift from the real cells.
  defp legend_swatch(:closed), do: "#{@swatch_base} bg-base-content/10 calendar-strike-after"
  defp legend_swatch(:override), do: "#{@swatch_base} ring-1 ring-inset ring-base-content/15 calendar-corner-before"
end
