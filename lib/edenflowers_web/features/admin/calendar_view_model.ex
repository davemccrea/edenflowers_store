defmodule EdenflowersWeb.Admin.CalendarViewModel do
  @moduledoc """
  View-model helpers for the admin calendar grid.

  The grid shows many fulfillment options at once, so these pure functions
  summarise a *set* of options into one cell, weekday header, or week. They
  aggregate per-option states, collapse disagreement to `:mixed`, and decide
  what a bulk toggle should do.

  The per-option booking rule lives in the domain
  (`Edenflowers.Fulfillment.Availability.admin_cell_state/3`); these helpers
  call into it.
  """

  alias Edenflowers.Fulfillment.{Availability, FulfillmentOption, KeyDates, Weekday}

  @type scope :: :all | String.t()

  @typedoc """
  `Availability.admin_cell_state/3` outputs plus `:mixed`, which arises only in
  the "All options" view when options disagree on a date.
  """
  @type cell_state :: Availability.admin_cell_state() | :mixed

  @spec scoped_options(scope(), [FulfillmentOption.t()]) :: [FulfillmentOption.t()]
  def scoped_options(:all, options), do: options
  def scoped_options(option_id, options), do: Enum.filter(options, &(&1.id == option_id))

  @spec cell_state(scope(), [FulfillmentOption.t()], Date.t(), Date.t()) :: cell_state()
  def cell_state(:all, options, %Date{} = date, %Date{} = today) do
    cell_state_for_options(options, date, today)
  end

  def cell_state(option_id, options, %Date{} = date, %Date{} = today) do
    case Enum.find(options, &(&1.id == option_id)) do
      nil -> :open
      option -> Availability.admin_cell_state(option, date, today)
    end
  end

  defp cell_state_for_options([], _date, _today), do: :open

  defp cell_state_for_options(options, date, today) when is_list(options) do
    options
    |> Enum.map(&Availability.admin_cell_state(&1, date, today))
    |> Enum.uniq()
    |> case do
      [single] -> single
      _multiple -> :mixed
    end
  end

  @spec weekday_state(scope(), [FulfillmentOption.t()], Weekday.t()) :: :on | :off | :mixed
  def weekday_state(:all, [], _weekday), do: :on

  def weekday_state(:all, options, weekday) do
    options
    |> Enum.map(&(weekday in &1.available_days))
    |> Enum.uniq()
    |> case do
      [true] -> :on
      [false] -> :off
      _mixed -> :mixed
    end
  end

  def weekday_state(option_id, options, weekday) do
    case Enum.find(options, &(&1.id == option_id)) do
      nil -> :on
      option -> if weekday in option.available_days, do: :on, else: :off
    end
  end

  @typedoc """
  Openness of a week across the current scope, for the per-week toggle button:

  - `:all_open` — every actionable (non-past) cell is open; also when the scope is empty.
  - `:all_closed` — every actionable cell is closed (weekday rule or override).
  - `:mixed` — cells within an option, or options with each other, disagree.
  - `:all_past` — the whole week is in the past; the button isn't actionable.
  """
  @type week_state :: :all_open | :all_closed | :mixed | :all_past

  @spec week_state(scope(), [FulfillmentOption.t()], [Date.t()], Date.t()) :: week_state()
  def week_state(scope, options, week, %Date{} = today) when is_list(week) do
    case scoped_options(scope, options) do
      [] ->
        :all_open

      list ->
        # Cross-option disagreement folds into :mixed — the bulk gesture is the
        # gesture for that case.
        states = Enum.map(list, &option_week_state(&1, week, today))

        cond do
          Enum.all?(states, &(&1 == :all_past)) -> :all_past
          Enum.all?(states, &(&1 == :all_open)) -> :all_open
          Enum.all?(states, &(&1 == :all_closed)) -> :all_closed
          true -> :mixed
        end
    end
  end

  defp option_week_state(%FulfillmentOption{} = option, week, %Date{} = today) when is_list(week) do
    actionable =
      week
      |> Enum.reject(&(Date.compare(&1, today) == :lt))
      |> Enum.reject(&KeyDates.key_date?/1)

    case actionable do
      [] ->
        :all_past

      dates ->
        states = Enum.map(dates, &Availability.admin_cell_state(option, &1, today))

        cond do
          Enum.all?(states, &(&1 == :open)) -> :all_open
          Enum.any?(states, &(&1 == :open)) -> :mixed
          true -> :all_closed
        end
    end
  end

  @spec weekday_toggle_direction([FulfillmentOption.t()], Weekday.t()) :: :on | :off
  def weekday_toggle_direction(options, weekday) when is_list(options) do
    if Enum.any?(options, &(weekday in &1.available_days)), do: :off, else: :on
  end

  @doc "Like `weekday_toggle_direction/2`, but `nil` when the week is entirely past (nothing to toggle)."
  @spec week_toggle_direction([FulfillmentOption.t()], [Date.t()], Date.t()) :: :open | :closed | nil
  def week_toggle_direction(options, week, %Date{} = today) when is_list(options) and is_list(week) do
    any_actionable? =
      Enum.any?(options, fn option -> option_week_state(option, week, today) != :all_past end)

    cond do
      not any_actionable? -> nil
      Enum.any?(options, fn option -> option_week_state(option, week, today) in [:all_open, :mixed] end) -> :closed
      true -> :open
    end
  end
end
