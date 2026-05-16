defmodule Edenflowers.Store.FulfillmentCalendar do
  @moduledoc """
  Pure functions for the admin date-toggle editor.

  Translates calendar clicks into updated attribute maps that the LiveView
  hands to `Ash.update/2`. Keeps click semantics out of the LiveView so they
  can be unit-tested without a socket or database.

  ## Click semantics

  - Clicking a **weekday header** toggles that weekday in `available_days`.
    This is the default rule for that weekday.

  - Clicking a **date cell** toggles an *override*:
    - If the date's weekday is currently available, the click adds the date
      to `disabled_dates` (closes that specific date).
    - If the date's weekday is currently unavailable, the click adds it to
      `enabled_dates` (opens that specific date).
    - Clicking an already-overridden date removes the override, returning
      the date to its weekday default.

  This means every click is reversible and the data shape stays minimal:
  no override is stored once a date matches its weekday default.
  """

  alias Edenflowers.{Fulfillments, Weekday}
  alias Edenflowers.Store.{FulfillmentOption, KeyDates}

  @weekdays [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday, :sunday]

  @typedoc "What the admin calendar is currently editing: every option, or one option by id."
  @type scope :: :all | String.t()

  @typedoc """
  `Fulfillments.admin_cell_state/3` outputs plus `:mixed`, which only happens
  in the admin "All options" view when options disagree on a date.
  """
  @type cell_state :: Fulfillments.admin_cell_state() | :mixed

  @doc """
  Whether the date's state is set by an explicit override rather than its
  weekday rule — i.e. the date appears in `enabled_dates` or `disabled_dates`.
  Used to mark cells that contradict the weekday default so admins can spot
  deliberate exceptions at a glance.
  """
  @spec override?(FulfillmentOption.t(), Date.t()) :: boolean()
  def override?(%FulfillmentOption{} = option, %Date{} = date) do
    date in option.enabled_dates or date in option.disabled_dates
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
    |> Enum.map(&Fulfillments.admin_cell_state(&1, date, today))
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

  @doc """
  Toggle a date for a single fulfillment option, returning the updated
  `%{enabled_dates: [...], disabled_dates: [...]}` map. Pass these to
  `Ash.update/2` to persist.

  See module doc for the click semantics.
  """
  @spec toggle_date(FulfillmentOption.t(), Date.t()) :: %{
          enabled_dates: [Date.t()],
          disabled_dates: [Date.t()]
        }
  def toggle_date(%FulfillmentOption{} = option, %Date{} = date) do
    enabled = option.enabled_dates
    disabled = option.disabled_dates

    cond do
      date in enabled ->
        %{enabled_dates: List.delete(enabled, date), disabled_dates: disabled}

      date in disabled ->
        %{enabled_dates: enabled, disabled_dates: List.delete(disabled, date)}

      weekday_available?(option, date) ->
        %{enabled_dates: enabled, disabled_dates: [date | disabled]}

      true ->
        %{enabled_dates: [date | enabled], disabled_dates: disabled}
    end
  end

  @doc """
  Set a weekday's rule for a single option to the given direction, returning
  the updated `%{available_days: [...], enabled_dates: [...], disabled_dates: [...]}`
  map. Idempotent — already-matching options pass through unchanged.

  Prunes any now-redundant overrides whose direction matches the new weekday
  rule: an `enabled_dates` entry on a now-available weekday is dropped (the
  rule already opens that date), and a `disabled_dates` entry on a now-closed
  weekday is dropped (the rule already closes it). This keeps the invariant
  "every override genuinely contradicts the weekday rule" so the override
  mark in the UI never lies.
  """
  @spec set_weekday(FulfillmentOption.t(), Weekday.t(), :on | :off) :: %{
          available_days: [Weekday.t()],
          enabled_dates: [Date.t()],
          disabled_dates: [Date.t()]
        }
  def set_weekday(%FulfillmentOption{} = option, weekday, direction)
      when weekday in @weekdays and direction in [:on, :off] do
    currently_available? = weekday in option.available_days

    available =
      case {direction, currently_available?} do
        {:on, false} -> [weekday | option.available_days]
        {:off, true} -> List.delete(option.available_days, weekday)
        _no_change -> option.available_days
      end

    enabled = Enum.reject(option.enabled_dates, &(Weekday.from_date(&1) in available))
    disabled = Enum.reject(option.disabled_dates, &(Weekday.from_date(&1) not in available))

    %{available_days: available, enabled_dates: enabled, disabled_dates: disabled}
    |> preserve_key_dates_on_weekday(option, weekday)
  end

  # After a weekday rule change, any key dates on that weekday whose open/closed
  # state would flip get an override restoring their pre-toggle state. Key dates
  # are never collaterally moved by a smart toggle — the florist has to click
  # them individually.
  defp preserve_key_dates_on_weekday(new_attrs, original_option, weekday) do
    virtual_option = struct(original_option, new_attrs)

    weekday
    |> key_dates_on_weekday()
    |> Enum.reduce(new_attrs, fn date, attrs ->
      old_open? = open?(original_option, date)
      new_open? = open?(virtual_option, date)

      if old_open? == new_open?, do: attrs, else: restore(attrs, date, old_open?)
    end)
  end

  # Key dates on `weekday` within the relevant lookahead. KeyDates lookups
  # are per-year, so we cover this year and next.
  defp key_dates_on_weekday(weekday) do
    year = Date.utc_today().year

    [year, year + 1]
    |> Enum.flat_map(&KeyDates.for_year/1)
    |> Enum.map(& &1.date)
    |> Enum.filter(&(Weekday.from_date(&1) == weekday))
  end

  # Past-agnostic openness — would the rule + overrides leave this date open?
  defp open?(option, date) do
    cond do
      date in option.disabled_dates -> false
      date in option.enabled_dates -> true
      true -> Weekday.from_date(date) in option.available_days
    end
  end

  defp restore(attrs, date, _was_open? = true) do
    %{
      attrs
      | enabled_dates: Enum.uniq([date | attrs.enabled_dates]),
        disabled_dates: List.delete(attrs.disabled_dates, date)
    }
  end

  defp restore(attrs, date, _was_open? = false) do
    %{
      attrs
      | disabled_dates: Enum.uniq([date | attrs.disabled_dates]),
        enabled_dates: List.delete(attrs.enabled_dates, date)
    }
  end

  @doc """
  Smart-toggle direction across a scope. If any option in `options` has the
  weekday available, the bulk gesture closes it everywhere; otherwise it
  opens it everywhere. The aggregate intent ("close it" / "open it") is the
  same single click whether viewed at one option or across all of them.
  """
  @spec weekday_toggle_direction([FulfillmentOption.t()], Weekday.t()) :: :on | :off
  def weekday_toggle_direction(options, weekday) when is_list(options) do
    if Enum.any?(options, &(weekday in &1.available_days)), do: :off, else: :on
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
    # Smart toggles never touch key dates, so they shouldn't drive the
    # button's state either — otherwise a week containing only a key date
    # would look actionable but the click would no-op.
    actionable =
      week
      |> Enum.reject(&(Date.compare(&1, today) == :lt))
      |> Enum.reject(&KeyDates.icon_for/1)

    case actionable do
      [] ->
        :all_past

      dates ->
        states = Enum.map(dates, &Fulfillments.admin_cell_state(option, &1, today))

        cond do
          Enum.all?(states, &(&1 == :open)) -> :all_open
          Enum.any?(states, &(&1 == :open)) -> :mixed
          true -> :all_closed
        end
    end
  end

  @doc """
  Set every non-past date in `week` to the given direction for a single
  option, returning the updated `%{enabled_dates: [...], disabled_dates: [...]}`
  map. Idempotent per-date: cells already in the target direction pass
  through unchanged.

  Each per-date flip uses the same minimal-override discipline as
  `toggle_date/2`: a redundant override (matching the weekday rule) is never
  written.
  """
  @spec set_week(FulfillmentOption.t(), [Date.t()], Date.t(), :open | :closed) :: %{
          enabled_dates: [Date.t()],
          disabled_dates: [Date.t()]
        }
  def set_week(%FulfillmentOption{} = option, week, %Date{} = today, direction)
      when is_list(week) and direction in [:open, :closed] do
    week
    |> Enum.reject(&(Date.compare(&1, today) == :lt))
    |> Enum.reject(&KeyDates.icon_for/1)
    |> Enum.reduce(%{enabled_dates: option.enabled_dates, disabled_dates: option.disabled_dates}, fn date, acc ->
      set_date(option, acc, date, direction)
    end)
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

  # Move a single date to the target direction in the given enabled/disabled
  # accumulator, without writing a redundant override.
  defp set_date(option, %{enabled_dates: enabled, disabled_dates: disabled}, date, :open) do
    cond do
      weekday_available?(option, date) ->
        %{enabled_dates: List.delete(enabled, date), disabled_dates: List.delete(disabled, date)}

      date in enabled ->
        %{enabled_dates: enabled, disabled_dates: List.delete(disabled, date)}

      true ->
        %{enabled_dates: [date | enabled], disabled_dates: List.delete(disabled, date)}
    end
  end

  defp set_date(option, %{enabled_dates: enabled, disabled_dates: disabled}, date, :closed) do
    cond do
      not weekday_available?(option, date) ->
        %{enabled_dates: List.delete(enabled, date), disabled_dates: List.delete(disabled, date)}

      date in disabled ->
        %{enabled_dates: List.delete(enabled, date), disabled_dates: disabled}

      true ->
        %{enabled_dates: List.delete(enabled, date), disabled_dates: [date | disabled]}
    end
  end

  defp weekday_available?(option, date) do
    Weekday.from_date(date) in option.available_days
  end

  @doc """
  Reset attributes for a full-wipe gesture: every weekday open, no overrides.

  Independent of the option's current state — this is a confirmed-destructive
  reset, not a toggle. Key-date protection deliberately does not apply: the
  florist has explicitly asked for everything to clear.
  """
  @spec reset() :: %{
          available_days: [Weekday.t()],
          enabled_dates: [Date.t()],
          disabled_dates: [Date.t()]
        }
  def reset do
    %{available_days: @weekdays, enabled_dates: [], disabled_dates: []}
  end
end
