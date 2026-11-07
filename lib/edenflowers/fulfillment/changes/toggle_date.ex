defmodule Edenflowers.Fulfillment.Changes.ToggleDate do
  @moduledoc """
  Toggles a date override in the shop calendar. Dates without an override
  switch away from their weekday rule; dates with an override return to it.
  Overrides are removed when the date matches its weekday rule.
  """
  use Ash.Resource.Change

  alias Edenflowers.Fulfillment.ShopCalendar
  alias Edenflowers.Fulfillment.Weekday

  @impl true
  def change(changeset, _opts, _context) do
    date = Ash.Changeset.get_argument(changeset, :date)
    calendar = changeset.data

    %{enabled_dates: enabled, disabled_dates: disabled} = toggle_date(calendar, date)

    changeset
    |> Ash.Changeset.force_change_attribute(:enabled_dates, enabled)
    |> Ash.Changeset.force_change_attribute(:disabled_dates, disabled)
  end

  @doc """
  Toggles a date, returning the updated
  `%{enabled_dates: [...], disabled_dates: [...]}` map.
  """
  @spec toggle_date(ShopCalendar.t(), Date.t()) :: %{
          enabled_dates: [Date.t()],
          disabled_dates: [Date.t()]
        }
  def toggle_date(%ShopCalendar{} = calendar, %Date{} = date) do
    enabled = calendar.enabled_dates
    disabled = calendar.disabled_dates

    cond do
      date in enabled ->
        %{enabled_dates: List.delete(enabled, date), disabled_dates: disabled}

      date in disabled ->
        %{enabled_dates: enabled, disabled_dates: List.delete(disabled, date)}

      Weekday.from_date(date) in calendar.available_days ->
        %{enabled_dates: enabled, disabled_dates: [date | disabled]}

      true ->
        %{enabled_dates: [date | enabled], disabled_dates: disabled}
    end
  end
end
