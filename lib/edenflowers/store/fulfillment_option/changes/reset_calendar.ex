defmodule Edenflowers.Store.FulfillmentOption.Changes.ResetCalendar do
  @moduledoc """
  Wipes the option's calendar attributes back to "fully open, no overrides"
  via `FulfillmentCalendar.reset/0`. Confirmed-destructive gesture — used by
  the admin reset button, not by smart toggles.
  """
  use Ash.Resource.Change

  alias Edenflowers.Store.FulfillmentCalendar

  @impl true
  def change(changeset, _opts, _context) do
    %{available_days: available, enabled_dates: enabled, disabled_dates: disabled} =
      FulfillmentCalendar.reset()

    changeset
    |> Ash.Changeset.force_change_attribute(:available_days, available)
    |> Ash.Changeset.force_change_attribute(:enabled_dates, enabled)
    |> Ash.Changeset.force_change_attribute(:disabled_dates, disabled)
  end
end
