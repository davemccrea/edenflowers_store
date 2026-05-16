defmodule Edenflowers.Store.FulfillmentCalendar do
  @moduledoc """
  Pure functions for the admin date-toggle editor.

  Translates calendar clicks into updated attribute maps that the LiveView
  hands to `Ash.update/2`. Keeps click semantics out of the LiveView so they
  can be unit-tested without a socket or database.

  ## Click semantics

  - Clicking a **weekday header** toggles that weekday in `available_days`.
    This is the default rule for that day of the week.

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

  alias Edenflowers.Fulfillments
  alias Edenflowers.Store.{FulfillmentOption, KeyDates}

  @weekdays [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday, :sunday]

  @type cell_state :: Fulfillments.cell_state() | :mixed

  @doc """
  Cell state for a single option, from the admin's point of view.

  Differs from `Fulfillments.cell_state/2` (the customer's view) in one way:
  same-day operational rules (deadlines, `same_day: false`) do not collapse
  today into `:past`. Today reflects whatever the availability rules say,
  so the admin can toggle it like any other date.

  `today` is passed in so this function stays pure — easy to test, and the
  view-model can compute it once per render rather than per cell.
  """
  @spec cell_state(FulfillmentOption.t(), Date.t(), Date.t()) :: cell_state()
  def cell_state(%FulfillmentOption{} = option, %Date{} = date, %Date{} = today) do
    cond do
      Date.compare(date, today) == :lt -> :past
      date in option.disabled_dates -> :override_off
      date in option.enabled_dates -> :open
      key_date?(date) -> :open
      weekday_available?(option, date) -> :open
      true -> :weekday_off
    end
  end

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
    |> Enum.map(&cell_state(&1, date, today))
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
  @spec weekday_state(:all | String.t(), [FulfillmentOption.t()], atom()) :: :on | :off | :mixed
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
  Single-date admin view: cell state, override flag, and the optional key-date
  name (used for the confirm prompt when an admin closes a holiday).

  Returns the three pieces together so the render function makes one call per
  cell instead of three. `override?` is intentionally `false` when scope is
  `:all` — across options, "some override, some don't" can't be summarized
  by one dot.
  """
  @type cell_view :: %{state: cell_state(), override?: boolean(), key_date_name: String.t() | nil}
  @spec view_model(:all | String.t(), [FulfillmentOption.t()], Date.t(), Date.t()) :: cell_view()
  def view_model(:all, options, date, today) do
    %{
      state: cell_state_for_options(options, date, today),
      override?: false,
      key_date_name: KeyDates.name_for(date)
    }
  end

  def view_model(option_id, options, date, today) do
    case Enum.find(options, &(&1.id == option_id)) do
      nil ->
        %{state: :open, override?: false, key_date_name: KeyDates.name_for(date)}

      option ->
        %{
          state: cell_state(option, date, today),
          override?: override?(option, date),
          key_date_name: KeyDates.name_for(date)
        }
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
        # Remove the explicit on-override. Date returns to its weekday default.
        %{enabled_dates: List.delete(enabled, date), disabled_dates: disabled}

      date in disabled ->
        # Remove the explicit off-override.
        %{enabled_dates: enabled, disabled_dates: List.delete(disabled, date)}

      open_by_rules?(option, date) ->
        # Currently open (by weekday rule or key-date protection) → close it.
        %{enabled_dates: enabled, disabled_dates: [date | disabled]}

      true ->
        # Currently closed by weekday rule → open it.
        %{enabled_dates: [date | enabled], disabled_dates: disabled}
    end
  end

  # Whether `date` is open given the option's rules — same predicate as
  # `cell_state`, minus the past-date check. `toggle_date` works on rules,
  # not the calendar clock, so a hypothetical past-date click should still
  # produce a sensible result.
  defp open_by_rules?(option, date) do
    cond do
      date in option.disabled_dates -> false
      date in option.enabled_dates -> true
      key_date?(date) -> true
      true -> weekday_available?(option, date)
    end
  end

  @doc """
  Toggle a weekday for a single fulfillment option, returning the updated
  `%{available_days: [...], enabled_dates: [...], disabled_dates: [...]}` map.

  Prunes any now-redundant overrides whose direction matches the new weekday
  rule: an `enabled_dates` entry on a now-available weekday is dropped (the
  rule already opens that date), and a `disabled_dates` entry on a now-closed
  weekday is dropped (the rule already closes it). This keeps the invariant
  "every override genuinely contradicts the weekday rule" so the override
  mark in the UI never lies.
  """
  @spec toggle_weekday(FulfillmentOption.t(), atom()) :: %{
          available_days: [atom()],
          enabled_dates: [Date.t()],
          disabled_dates: [Date.t()]
        }
  def toggle_weekday(%FulfillmentOption{} = option, weekday) when weekday in @weekdays do
    available =
      if weekday in option.available_days do
        List.delete(option.available_days, weekday)
      else
        [weekday | option.available_days]
      end

    # An override is stale when its presence and absence yield the same
    # cell_state. For enabled_dates: open by rule, or a key date (which is
    # protected regardless). For disabled_dates: closed by rule AND not a key
    # date (key dates need the explicit disable to stay closed).
    enabled =
      Enum.reject(option.enabled_dates, fn date ->
        weekday_atom(date) in available or key_date?(date)
      end)

    disabled =
      Enum.reject(option.disabled_dates, fn date ->
        weekday_atom(date) not in available and not key_date?(date)
      end)

    %{available_days: available, enabled_dates: enabled, disabled_dates: disabled}
  end

  defp weekday_available?(option, date) do
    weekday_atom(date) in option.available_days
  end

  defp key_date?(date), do: not is_nil(KeyDates.icon_for(date))

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
end
