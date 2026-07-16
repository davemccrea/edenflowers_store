defmodule Edenflowers.Fulfillment.FulfillmentOption.Changes.SetWeekday do
  @moduledoc """
  Sets a weekday's availability rule to `:on` or `:off` for a fulfillment
  option, idempotently.

  Prunes any now-redundant overrides whose direction matches the new weekday
  rule: an `enabled_dates` entry on a now-available weekday is dropped (the
  rule already opens that date), and a `disabled_dates` entry on a now-closed
  weekday is dropped (the rule already closes it). This keeps the invariant
  "every override genuinely contradicts the weekday rule" so the override mark
  in the UI never lies.

  `set_weekday/3` is a pure function kept public so the rule logic can be
  unit-tested without a DB roundtrip; `change/3` just applies its result.
  """
  use Ash.Resource.Change

  alias Edenflowers.Fulfillment.{FulfillmentOption, KeyDates, Weekday}

  @weekdays [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday, :sunday]

  @impl true
  def change(changeset, _opts, _context) do
    weekday = Ash.Changeset.get_argument(changeset, :weekday)
    direction = Ash.Changeset.get_argument(changeset, :direction)
    option = changeset.data

    %{available_days: available, enabled_dates: enabled, disabled_dates: disabled} =
      set_weekday(option, weekday, direction)

    changeset
    |> Ash.Changeset.force_change_attribute(:available_days, available)
    |> Ash.Changeset.force_change_attribute(:enabled_dates, enabled)
    |> Ash.Changeset.force_change_attribute(:disabled_dates, disabled)
  end

  @doc """
  Set a weekday's rule for a single option to the given direction, returning
  the updated `%{available_days: [...], enabled_dates: [...], disabled_dates: [...]}`
  map. Idempotent — already-matching options pass through unchanged.
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
    |> KeyDates.dates_for_weekday()
    |> Enum.reduce(new_attrs, fn date, attrs ->
      old_open? = open?(original_option, date)
      new_open? = open?(virtual_option, date)

      if old_open? == new_open?, do: attrs, else: restore(attrs, date, old_open?)
    end)
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
end
