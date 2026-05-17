defmodule Edenflowers.Store.FulfillmentOption.Changes.SetWeekday do
  @moduledoc """
  Applies the directional per-weekday rule change from
  `FulfillmentCalendar.set_weekday/3` to the changeset. Delegates to the
  pure function so the calculation stays unit-testable without a DB
  roundtrip.
  """
  use Ash.Resource.Change

  alias Edenflowers.Store.FulfillmentCalendar

  @impl true
  def change(changeset, _opts, _context) do
    weekday = Ash.Changeset.get_argument(changeset, :weekday)
    direction = Ash.Changeset.get_argument(changeset, :direction)
    option = changeset.data

    %{available_days: available, enabled_dates: enabled, disabled_dates: disabled} =
      FulfillmentCalendar.set_weekday(option, weekday, direction)

    changeset
    |> Ash.Changeset.force_change_attribute(:available_days, available)
    |> Ash.Changeset.force_change_attribute(:enabled_dates, enabled)
    |> Ash.Changeset.force_change_attribute(:disabled_dates, disabled)
  end
end
