defmodule Edenflowers.Fulfillment.FulfillmentOption.Changes.SetWeek do
  @moduledoc """
  Sets every non-past date in a week to `:open` or `:closed` for a fulfillment
  option, idempotently per-date: cells already in the target direction pass
  through unchanged.

  Each per-date flip uses the same minimal-override discipline as
  `ToggleDate.toggle_date/2`: a redundant override (matching the weekday rule)
  is never written. Key dates in the week are skipped — the florist toggles
  those individually.

  `set_week/4` is a pure function kept public so the per-week logic can be
  unit-tested without a DB roundtrip; `change/3` just applies its result.
  """
  use Ash.Resource.Change

  alias Edenflowers.Fulfillment.{FulfillmentOption, KeyDates, Weekday}

  @impl true
  def change(changeset, _opts, _context) do
    week = Ash.Changeset.get_argument(changeset, :week)
    today = Ash.Changeset.get_argument(changeset, :today)
    direction = Ash.Changeset.get_argument(changeset, :direction)
    option = changeset.data

    %{enabled_dates: enabled, disabled_dates: disabled} = set_week(option, week, today, direction)

    changeset
    |> Ash.Changeset.force_change_attribute(:enabled_dates, enabled)
    |> Ash.Changeset.force_change_attribute(:disabled_dates, disabled)
  end

  @doc """
  Set every non-past date in `week` to the given direction for a single
  option, returning the updated `%{enabled_dates: [...], disabled_dates: [...]}`
  map. Idempotent per-date.
  """
  @spec set_week(FulfillmentOption.t(), [Date.t()], Date.t(), :open | :closed) :: %{
          enabled_dates: [Date.t()],
          disabled_dates: [Date.t()]
        }
  def set_week(%FulfillmentOption{} = option, week, %Date{} = today, direction)
      when is_list(week) and direction in [:open, :closed] do
    initial = %{enabled_dates: option.enabled_dates, disabled_dates: option.disabled_dates}

    week
    |> Enum.reject(&(Date.compare(&1, today) == :lt))
    |> Enum.reject(&KeyDates.key_date?/1)
    |> Enum.reduce(initial, fn date, acc -> set_date(option, acc, date, direction) end)
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
end
