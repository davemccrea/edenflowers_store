defmodule Edenflowers.Store.FulfillmentOption.Changes.ToggleWeekday do
  @moduledoc """
  Applies the weekday-toggle semantics from `FulfillmentCalendar.toggle_weekday/2`
  to the changeset. Delegates to the pure function so the calculation stays
  unit-testable without a DB roundtrip.
  """
  use Ash.Resource.Change

  alias Edenflowers.Store.FulfillmentCalendar

  @impl true
  def change(changeset, _opts, _context) do
    weekday = Ash.Changeset.get_argument(changeset, :weekday)
    option = changeset.data

    %{available_days: available, enabled_dates: enabled, disabled_dates: disabled} =
      FulfillmentCalendar.toggle_weekday(option, weekday)

    changeset
    |> Ash.Changeset.force_change_attribute(:available_days, available)
    |> Ash.Changeset.force_change_attribute(:enabled_dates, enabled)
    |> Ash.Changeset.force_change_attribute(:disabled_dates, disabled)
  end
end
