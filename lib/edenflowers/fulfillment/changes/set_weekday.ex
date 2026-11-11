defmodule Edenflowers.Fulfillment.Changes.SetWeekday do
  @moduledoc """
  Sets a weekday's availability rule to `:on` or `:off` and removes redundant
  date overrides. Key dates on that weekday retain their previous open or
  closed state for the current and following year, using overrides as needed.
  """
  use Ash.Resource.Change

  alias Edenflowers.Fulfillment.KeyDates
  alias Edenflowers.Fulfillment.ShopCalendar
  alias Edenflowers.Fulfillment.Weekday

  @impl true
  def change(changeset, _opts, _context) do
    weekday = Ash.Changeset.get_argument(changeset, :weekday)
    direction = Ash.Changeset.get_argument(changeset, :direction)
    calendar = changeset.data

    %{available_days: available, enabled_dates: enabled, disabled_dates: disabled} =
      set_weekday(calendar, weekday, direction)

    changeset
    |> Ash.Changeset.force_change_attribute(:available_days, available)
    |> Ash.Changeset.force_change_attribute(:enabled_dates, enabled)
    |> Ash.Changeset.force_change_attribute(:disabled_dates, disabled)
  end

  @doc """
  Sets a weekday's rule, returning the updated
  `%{available_days: [...], enabled_dates: [...], disabled_dates: [...]}` map.
  Repeating the same change leaves the calendar unchanged.
  """
  @spec set_weekday(ShopCalendar.t(), Weekday.t(), :on | :off) :: %{
          available_days: [Weekday.t()],
          enabled_dates: [Date.t()],
          disabled_dates: [Date.t()]
        }
  def set_weekday(%ShopCalendar{} = calendar, weekday, direction)
      when direction in [:on, :off] do
    currently_available? = weekday in calendar.available_days

    available =
      case {direction, currently_available?} do
        {:on, false} -> [weekday | calendar.available_days]
        {:off, true} -> List.delete(calendar.available_days, weekday)
        _no_change -> calendar.available_days
      end

    enabled = Enum.reject(calendar.enabled_dates, &(Weekday.from_date(&1) in available))
    disabled = Enum.reject(calendar.disabled_dates, &(Weekday.from_date(&1) not in available))

    %{available_days: available, enabled_dates: enabled, disabled_dates: disabled}
    |> preserve_key_dates_on_weekday(calendar, weekday)
  end

  # After a weekday rule change, any key dates on that weekday whose open/closed
  # state would flip get an override restoring their pre-toggle state. Key dates
  # are never collaterally moved by a smart toggle — the florist has to click
  # them individually.
  defp preserve_key_dates_on_weekday(new_attrs, original_calendar, weekday) do
    virtual_calendar = struct(original_calendar, new_attrs)

    weekday
    |> KeyDates.dates_for_weekday()
    |> Enum.reduce(new_attrs, fn date, attrs ->
      old_open? = open?(original_calendar, date)
      new_open? = open?(virtual_calendar, date)

      if old_open? == new_open?, do: attrs, else: restore(attrs, date, old_open?)
    end)
  end

  # Check the weekday rule and date overrides without treating past dates as closed.
  defp open?(calendar, date) do
    cond do
      date in calendar.disabled_dates -> false
      date in calendar.enabled_dates -> true
      true -> Weekday.from_date(date) in calendar.available_days
    end
  end

  defp restore(attrs, date, true = _was_open?) do
    %{
      attrs
      | enabled_dates: Enum.uniq([date | attrs.enabled_dates]),
        disabled_dates: List.delete(attrs.disabled_dates, date)
    }
  end

  defp restore(attrs, date, false = _was_open?) do
    %{
      attrs
      | disabled_dates: Enum.uniq([date | attrs.disabled_dates]),
        enabled_dates: List.delete(attrs.enabled_dates, date)
    }
  end
end
