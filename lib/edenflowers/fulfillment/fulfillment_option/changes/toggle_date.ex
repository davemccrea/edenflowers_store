defmodule Edenflowers.Fulfillment.FulfillmentOption.Changes.ToggleDate do
  @moduledoc """
  Toggles a single date on or off in a fulfillment option's overrides.

  ## Click semantics

  Clicking a date cell toggles an *override*:

    - If the date's weekday is currently available, the click adds the date
      to `disabled_dates` (closes that specific date).
    - If the date's weekday is currently unavailable, the click adds it to
      `enabled_dates` (opens that specific date).
    - Clicking an already-overridden date removes the override, returning the
      date to its weekday default.

  Every click is reversible and no override is stored once a date matches its
  weekday default, keeping the data shape minimal.

  `toggle_date/2` is a pure function kept public so the click semantics can be
  unit-tested without a DB roundtrip; `change/3` just applies its result.
  """
  use Ash.Resource.Change

  alias Edenflowers.Fulfillment.{FulfillmentOption, Weekday}

  @impl true
  def change(changeset, _opts, _context) do
    date = Ash.Changeset.get_argument(changeset, :date)
    option = changeset.data

    %{enabled_dates: enabled, disabled_dates: disabled} = toggle_date(option, date)

    changeset
    |> Ash.Changeset.force_change_attribute(:enabled_dates, enabled)
    |> Ash.Changeset.force_change_attribute(:disabled_dates, disabled)
  end

  @doc """
  Toggle a date for a single fulfillment option, returning the updated
  `%{enabled_dates: [...], disabled_dates: [...]}` map. See module doc for the
  click semantics.
  """
  @spec toggle_date(FulfillmentOption.t(), Date.t()) :: %{
          enabled_dates: [Date.t()],
          disabled_dates: [Date.t()]
        }
  def toggle_date(%FulfillmentOption{} = option, %Date{} = date) do
    enabled = option.enabled_dates
    disabled = option.disabled_dates

    cond do
      date in enabled ->
        %{enabled_dates: List.delete(enabled, date), disabled_dates: disabled}

      date in disabled ->
        %{enabled_dates: enabled, disabled_dates: List.delete(disabled, date)}

      Weekday.from_date(date) in option.available_days ->
        %{enabled_dates: enabled, disabled_dates: [date | disabled]}

      true ->
        %{enabled_dates: [date | enabled], disabled_dates: disabled}
    end
  end
end
