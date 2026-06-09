defmodule Edenflowers.Fulfillment.FulfillmentOption.Changes.SetWeek do
  @moduledoc """
  Applies the directional per-week date change from
  `FulfillmentCalendar.set_week/4` to the changeset. Delegates to the pure
  function so the calculation stays unit-testable without a DB roundtrip.
  """
  use Ash.Resource.Change

  alias Edenflowers.Fulfillment.FulfillmentCalendar

  @impl true
  def change(changeset, _opts, _context) do
    week = Ash.Changeset.get_argument(changeset, :week)
    today = Ash.Changeset.get_argument(changeset, :today)
    direction = Ash.Changeset.get_argument(changeset, :direction)
    option = changeset.data

    %{enabled_dates: enabled, disabled_dates: disabled} =
      FulfillmentCalendar.set_week(option, week, today, direction)

    changeset
    |> Ash.Changeset.force_change_attribute(:enabled_dates, enabled)
    |> Ash.Changeset.force_change_attribute(:disabled_dates, disabled)
  end
end
