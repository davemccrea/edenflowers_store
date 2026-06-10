defmodule Edenflowers.Fulfillment.FulfillmentOption.Changes.ResetCalendar do
  @moduledoc """
  Wipes the option's calendar attributes back to "fully open, no overrides".

  Confirmed-destructive gesture — used by the admin reset button, not by smart
  toggles. Independent of the option's current state, and key-date protection
  deliberately does not apply: the florist has explicitly asked for everything
  to clear.

  `reset/0` is a pure function kept public so the reset shape can be unit-tested
  without a DB roundtrip; `change/3` just applies its result.
  """
  use Ash.Resource.Change

  alias Edenflowers.Fulfillment.Weekday

  @weekdays [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday, :sunday]

  @impl true
  def change(changeset, _opts, _context) do
    %{available_days: available, enabled_dates: enabled, disabled_dates: disabled} = reset()

    changeset
    |> Ash.Changeset.force_change_attribute(:available_days, available)
    |> Ash.Changeset.force_change_attribute(:enabled_dates, enabled)
    |> Ash.Changeset.force_change_attribute(:disabled_dates, disabled)
  end

  @doc "Attributes for a full-wipe gesture: every weekday open, no overrides."
  @spec reset() :: %{
          available_days: [Weekday.t()],
          enabled_dates: [Date.t()],
          disabled_dates: [Date.t()]
        }
  def reset do
    %{available_days: @weekdays, enabled_dates: [], disabled_dates: []}
  end
end
