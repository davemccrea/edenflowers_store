defmodule Edenflowers.Fulfillment.Changes.SetWeekday do
  @moduledoc """
  Sets a weekday's availability rule to `:on` or `:off` and removes redundant
  date overrides. Key dates are open whatever their weekday, so the ones Jennie
  closed keep their override.
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

    disabled =
      Enum.reject(calendar.disabled_dates, &(Weekday.from_date(&1) not in available and not KeyDates.key_date?(&1)))

    %{available_days: available, enabled_dates: enabled, disabled_dates: disabled}
  end
end
