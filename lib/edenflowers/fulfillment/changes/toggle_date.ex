defmodule Edenflowers.Fulfillment.Changes.ToggleDate do
  @moduledoc """
  Toggles a date in the shop calendar: an open date closes and a closed one
  opens. An override is only kept while the date differs from its rule (its
  weekday, or open for a key date).
  """
  use Ash.Resource.Change

  alias Edenflowers.Fulfillment.Availability
  alias Edenflowers.Fulfillment.ShopCalendar

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
      date in disabled ->
        %{enabled_dates: enabled, disabled_dates: List.delete(disabled, date)}

      Availability.open_by_rule?(calendar, date) ->
        %{enabled_dates: List.delete(enabled, date), disabled_dates: [date | disabled]}

      date in enabled ->
        %{enabled_dates: List.delete(enabled, date), disabled_dates: disabled}

      true ->
        %{enabled_dates: [date | enabled], disabled_dates: disabled}
    end
  end
end
