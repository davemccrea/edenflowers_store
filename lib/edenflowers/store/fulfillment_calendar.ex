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
  alias Edenflowers.Store.FulfillmentOption

  @weekdays [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday, :sunday]

  @type cell_state :: Fulfillments.cell_state() | :mixed

  @doc """
  Cell state for a single option (delegates to `Fulfillments.cell_state/3`).
  """
  @spec cell_state(FulfillmentOption.t(), Date.t()) :: cell_state()
  def cell_state(%FulfillmentOption{} = option, date) do
    Fulfillments.cell_state(option, date)
  end

  @doc """
  Cell state across multiple options. Returns `:mixed` when options disagree
  on whether the date is open — used by the "All options" admin view to
  signal that the florist must pick a specific option to disambiguate.
  """
  @spec cell_state_for_options([FulfillmentOption.t()], Date.t()) :: cell_state()
  def cell_state_for_options([], _date), do: :open

  def cell_state_for_options(options, date) when is_list(options) do
    options
    |> Enum.map(&cell_state(&1, date))
    |> Enum.uniq()
    |> case do
      [single] -> single
      _multiple -> :mixed
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

      weekday_available?(option, date) ->
        # Currently open by weekday default → add an off-override.
        %{enabled_dates: enabled, disabled_dates: [date | disabled]}

      true ->
        # Currently closed by weekday default → add an on-override.
        %{enabled_dates: [date | enabled], disabled_dates: disabled}
    end
  end

  @doc """
  Toggle a weekday for a single fulfillment option, returning the updated
  `%{available_days: [...]}` map.

  When toggling a weekday off, any explicit `enabled_dates` whose weekday
  matches are preserved (they remain explicit on-overrides). Similarly for
  the inverse direction — overrides survive weekday-level flips.
  """
  @spec toggle_weekday(FulfillmentOption.t(), atom()) :: %{available_days: [atom()]}
  def toggle_weekday(%FulfillmentOption{} = option, weekday) when weekday in @weekdays do
    available =
      if weekday in option.available_days do
        List.delete(option.available_days, weekday)
      else
        [weekday | option.available_days]
      end

    %{available_days: available}
  end

  defp weekday_available?(option, date) do
    weekday_atom(date) in option.available_days
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
end
