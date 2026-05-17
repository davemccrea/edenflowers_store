defmodule Edenflowers.Store.FulfillmentOption.Changes.ToggleDate do
  @moduledoc """
  Applies the per-date toggle semantics from `FulfillmentCalendar.toggle_date/2`
  to the changeset. Delegates to the pure function so the calculation stays
  unit-testable without a DB roundtrip.
  """
  use Ash.Resource.Change

  alias Edenflowers.Store.FulfillmentCalendar

  @impl true
  def change(changeset, _opts, _context) do
    date = Ash.Changeset.get_argument(changeset, :date)
    option = changeset.data

    %{enabled_dates: enabled, disabled_dates: disabled} =
      FulfillmentCalendar.toggle_date(option, date)

    changeset
    |> Ash.Changeset.force_change_attribute(:enabled_dates, enabled)
    |> Ash.Changeset.force_change_attribute(:disabled_dates, disabled)
  end
end
