defmodule Edenflowers.Fulfillment.Changes.SetWeek do
  @moduledoc """
  Sets a week's non-past dates to `:open` or `:closed`, skipping key dates.
  Overrides are removed when the target matches the weekday rule.
  Repeating the same change leaves the calendar unchanged.
  """
  use Ash.Resource.Change

  alias Edenflowers.Fulfillment.KeyDates
  alias Edenflowers.Fulfillment.ShopCalendar
  alias Edenflowers.Fulfillment.Weekday

  @impl true
  def change(changeset, _opts, _context) do
    week = Ash.Changeset.get_argument(changeset, :week)
    today = Ash.Changeset.get_argument(changeset, :today)
    direction = Ash.Changeset.get_argument(changeset, :direction)
    calendar = changeset.data

    %{enabled_dates: enabled, disabled_dates: disabled} = set_week(calendar, week, today, direction)

    changeset
    |> Ash.Changeset.force_change_attribute(:enabled_dates, enabled)
    |> Ash.Changeset.force_change_attribute(:disabled_dates, disabled)
  end

  @doc """
  Sets dates in `week` to the given direction, skipping past dates and key dates.
  Returns the updated `%{enabled_dates: [...], disabled_dates: [...]}` map.
  """
  @spec set_week(ShopCalendar.t(), [Date.t()], Date.t(), :open | :closed) :: %{
          enabled_dates: [Date.t()],
          disabled_dates: [Date.t()]
        }
  def set_week(%ShopCalendar{} = calendar, week, %Date{} = today, direction)
      when is_list(week) and direction in [:open, :closed] do
    initial = %{enabled_dates: calendar.enabled_dates, disabled_dates: calendar.disabled_dates}

    week
    |> Enum.reject(&(Date.before?(&1, today) or KeyDates.key_date?(&1)))
    |> Enum.reduce(initial, fn date, acc -> set_date(calendar, acc, date, direction) end)
  end

  # Move a single date to the target direction in the given enabled/disabled
  # accumulator, without writing a redundant override.
  defp set_date(calendar, %{enabled_dates: enabled, disabled_dates: disabled}, date, :open) do
    cond do
      weekday_available?(calendar, date) ->
        %{enabled_dates: List.delete(enabled, date), disabled_dates: List.delete(disabled, date)}

      date in enabled ->
        %{enabled_dates: enabled, disabled_dates: List.delete(disabled, date)}

      true ->
        %{enabled_dates: [date | enabled], disabled_dates: List.delete(disabled, date)}
    end
  end

  defp set_date(calendar, %{enabled_dates: enabled, disabled_dates: disabled}, date, :closed) do
    cond do
      not weekday_available?(calendar, date) ->
        %{enabled_dates: List.delete(enabled, date), disabled_dates: List.delete(disabled, date)}

      date in disabled ->
        %{enabled_dates: List.delete(enabled, date), disabled_dates: disabled}

      true ->
        %{enabled_dates: List.delete(enabled, date), disabled_dates: [date | disabled]}
    end
  end

  defp weekday_available?(calendar, date) do
    Weekday.from_date(date) in calendar.available_days
  end
end
