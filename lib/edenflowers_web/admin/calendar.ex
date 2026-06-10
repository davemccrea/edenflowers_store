defmodule EdenflowersWeb.Admin.Calendar do
  @moduledoc """
  Admin calendar view-model helpers.

  Pure functions that summarise a *set* of fulfillment options for the admin
  grid: aggregating per-option cell states into one cell (collapsing
  disagreement to `:mixed`), classifying weekday headers and weeks, and
  deciding what a bulk toggle should do. They exist because the admin grid
  renders many options at once — a non-UI caller would never need `:mixed` or
  `:all_past`.

  The per-option booking rule itself lives in the domain
  (`Edenflowers.Fulfillment.Availability.admin_cell_state/3`); these
  helpers call into it.
  """

  alias Edenflowers.Fulfillment.{Availability, FulfillmentOption, KeyDates, Weekday}

  @typedoc "Which fulfillment options the admin grid is showing: every option, or one by id."
  @type scope :: :all | String.t()

  @typedoc """
  `Availability.admin_cell_state/3` outputs plus `:mixed`, which only
  happens in the admin "All options" view when options disagree on a date.
  """
  @type cell_state :: Availability.admin_cell_state() | :mixed

  @doc """
  Narrow `options` to the current scope. `:all` returns everything; a UUID
  string returns the single option (or `[]` when not found).
  """
  @spec scoped_options(scope(), [FulfillmentOption.t()]) :: [FulfillmentOption.t()]
  def scoped_options(:all, options), do: options
  def scoped_options(option_id, options), do: Enum.filter(options, &(&1.id == option_id))

  @doc """
  Cell state for the current scope. `:all` aggregates across every option
  (collapsing disagreement to `:mixed`); a single-option scope returns that
  option's admin cell state. Returns `:open` when the scoped id is unknown
  so the cell renders sensibly rather than blowing up.
  """
  @spec cell_state_for_scope(scope(), [FulfillmentOption.t()], Date.t(), Date.t()) :: cell_state()
  def cell_state_for_scope(:all, options, %Date{} = date, %Date{} = today) do
    cell_state_for_options(options, date, today)
  end

  def cell_state_for_scope(option_id, options, %Date{} = date, %Date{} = today) do
    case Enum.find(options, &(&1.id == option_id)) do
      nil -> :open
      option -> Availability.admin_cell_state(option, date, today)
    end
  end

  @doc """
  Cell state across multiple options. Returns `:mixed` when options disagree
  on whether the date is open — used by the "All options" admin view to
  signal that the florist must pick a specific option to disambiguate.
  """
  @spec cell_state_for_options([FulfillmentOption.t()], Date.t(), Date.t()) :: cell_state()
  def cell_state_for_options([], _date, _today), do: :open

  def cell_state_for_options(options, date, today) when is_list(options) do
    options
    |> Enum.map(&Availability.admin_cell_state(&1, date, today))
    |> Enum.uniq()
    |> case do
      [single] -> single
      _multiple -> :mixed
    end
  end

  @doc """
  Weekday state across the current scope.

  - `:on` — every option in scope has the weekday available.
  - `:off` — no option in scope has the weekday available.
  - `:mixed` — options disagree.

  Scope is either `:all` (every option) or a single option id (UUID string).
  Returns `:on` when the scoped option can't be found so the header keeps a
  sensible default rather than disappearing.
  """
  @spec weekday_state(scope(), [FulfillmentOption.t()], Weekday.t()) :: :on | :off | :mixed
  def weekday_state(:all, [], _weekday), do: :on

  def weekday_state(:all, options, weekday) do
    options
    |> Enum.map(&(weekday in &1.available_days))
    |> Enum.uniq()
    |> case do
      [true] -> :on
      [false] -> :off
      _mixed -> :mixed
    end
  end

  def weekday_state(option_id, options, weekday) do
    case Enum.find(options, &(&1.id == option_id)) do
      nil -> :on
      option -> if weekday in option.available_days, do: :on, else: :off
    end
  end

  @typedoc """
  Summary of a week's openness for one option, used to label and enable/disable
  the per-week toggle button.

  - `:all_open` — every non-past cell in the week is open.
  - `:all_closed` — every non-past cell is closed (by weekday rule or override).
  - `:mixed` — some non-past cells are open, others closed.
  - `:all_past` — every cell in the week is in the past; the week isn't actionable.
  """
  @type week_state :: :all_open | :all_closed | :mixed | :all_past

  @doc """
  Classify a week's openness for one option, against `today`. Used by the
  per-week toggle button to pick its label and to disable itself when the
  whole week is in the past.
  """
  @spec week_state(FulfillmentOption.t(), [Date.t()], Date.t()) :: week_state()
  def week_state(%FulfillmentOption{} = option, week, %Date{} = today) when is_list(week) do
    actionable =
      week
      |> Enum.reject(&(Date.compare(&1, today) == :lt))
      |> Enum.reject(&KeyDates.key_date?/1)

    case actionable do
      [] ->
        :all_past

      dates ->
        states = Enum.map(dates, &Availability.admin_cell_state(option, &1, today))

        cond do
          Enum.all?(states, &(&1 == :open)) -> :all_open
          Enum.any?(states, &(&1 == :open)) -> :mixed
          true -> :all_closed
        end
    end
  end

  @doc """
  Smart-toggle direction across a scope. If any option has the weekday
  available, the bulk gesture closes it everywhere; otherwise it opens it
  everywhere.
  """
  @spec weekday_toggle_direction([FulfillmentOption.t()], Weekday.t()) :: :on | :off
  def weekday_toggle_direction(options, weekday) when is_list(options) do
    if Enum.any?(options, &(weekday in &1.available_days)), do: :off, else: :on
  end

  @doc """
  Smart-toggle direction across a scope. If any option has at least one open
  non-past cell in the week, the bulk gesture closes the week everywhere;
  otherwise it opens what's closed. Returns `nil` when no option has any
  actionable (non-past) cell — the week is entirely past, nothing to do.
  """
  @spec week_toggle_direction([FulfillmentOption.t()], [Date.t()], Date.t()) :: :open | :closed | nil
  def week_toggle_direction(options, week, %Date{} = today) when is_list(options) and is_list(week) do
    any_actionable? =
      Enum.any?(options, fn option -> week_state(option, week, today) != :all_past end)

    cond do
      not any_actionable? -> nil
      Enum.any?(options, fn option -> week_state(option, week, today) in [:all_open, :mixed] end) -> :closed
      true -> :open
    end
  end
end
