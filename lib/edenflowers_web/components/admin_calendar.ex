defmodule EdenflowersWeb.AdminCalendar do
  @moduledoc """
  The admin month grid for the shop calendar.

  Every date, weekday header and week toggle is a button that sends its event
  straight to the LiveView: `"toggle-date"`, `"toggle-weekday"`,
  `"toggle-week"`. `EdenflowersWeb.MonthGrid` draws the month and handles
  month navigation and the keyboard; this module fills its slots.
  """
  use EdenflowersWeb, :html

  import EdenflowersWeb.KeyDateIcon

  alias Edenflowers.Fulfillment.Availability
  alias Edenflowers.Fulfillment.KeyDates
  alias Edenflowers.Fulfillment.Weekday
  alias EdenflowersWeb.MonthGrid

  @swatch_base "relative inline-block w-4 h-4 mr-2 mt-0.5 shrink-0"

  attr :id, :string, required: true
  attr :calendar, :any, required: true, doc: "`ShopCalendar.t()`"
  attr :today, :any, required: true, doc: "`Date.t()` — passed in so render stays pure"

  def admin_calendar(assigns) do
    ~H"""
    <.live_component module={MonthGrid} id={@id} today={@today}>
      <:weekday :let={day}>
        <% open? = Weekday.from_date(day) in @calendar.available_days %>
        <button
          type="button"
          phx-click="toggle-weekday"
          phx-value-weekday={Weekday.from_date(day)}
          aria-label={weekday_aria_label(day, open?)}
          class={weekday_class(open?)}
        >
          {Localize.DateTime.to_string!(day, format: "EEEEEE")}
        </button>
      </:weekday>
      <:week :let={week}>
        <% direction = week_toggle_direction(@calendar, week, @today) %>
        <button
          type="button"
          phx-click="toggle-week"
          phx-value-week={List.first(week)}
          disabled={is_nil(direction)}
          aria-label={week_aria_label(week)}
          class={week_class(direction)}
        >
          <.icon name="hero-arrows-right-left" class="h-3 w-3" />
        </button>
      </:week>
      <:day :let={%{date: day, attrs: attrs}}>
        <% state = Availability.admin_cell_state(@calendar, day, @today) %>
        <button
          {attrs}
          type="button"
          phx-click="toggle-date"
          phx-value-date={day}
          aria-label={day_aria_label(day, @today, state)}
          aria-current={if day == @today, do: "date"}
          aria-disabled={if state == :past, do: "true"}
          class={cell_class(state, day == @today, Availability.override?(@calendar, day))}
        >
          <time datetime={Date.to_iso8601(day)} aria-hidden="true" class="relative z-10">
            {Localize.DateTime.to_string!(day, format: "d")}
          </time>
          <.key_date_icon date={day} selected?={false} muted?={state == :past} />
        </button>
      </:day>
      <:footer :let={month}>
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
    <div class="text-sm md:max-w-xs md:pt-2">
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
    </div>
    """
  end

  defp weekday_aria_label(date, open?) do
    weekday = Localize.DateTime.to_string!(date, format: "cccc")
    state = if open?, do: ~t"open", else: ~t"closed"
    "#{~t"Toggle #{weekday}"}, #{state}"
  end

  defp week_aria_label(week) do
    first = Edenflowers.Format.day_month(List.first(week), Edenflowers.Format.locale())
    last = Edenflowers.Format.day_month(List.last(week), Edenflowers.Format.locale())
    ~t"Toggle week #{first} to #{last}"
  end

  defp day_aria_label(day, today, state) do
    date = Localize.Date.to_string!(day, format: :full)

    if day == today,
      do: "#{date}, #{~t"today"}, #{state_label(state)}",
      else: "#{date}, #{state_label(state)}"
  end

  defp state_label(:open), do: ~t"open"
  defp state_label(:weekday_disabled), do: ~t"closed"
  defp state_label(:date_disabled), do: ~t"closed"
  defp state_label(:past), do: ~t"past"

  defp cell_class(state, today?, override?) do
    base = "relative aspect-square text-sm font-medium leading-none flex items-center justify-center"

    closed_class =
      "cursor-pointer bg-base-content/10 text-base-content/65 hover:bg-primary/10 calendar-strike-after hover:after:bg-error"

    state_class =
      case state do
        :open -> "cursor-pointer text-base-content/85 hover:bg-primary/10"
        :weekday_disabled -> closed_class
        :date_disabled -> closed_class
        :past -> "cursor-not-allowed text-base-content/25"
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
