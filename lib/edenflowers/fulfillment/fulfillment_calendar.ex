defmodule Edenflowers.Fulfillment.FulfillmentCalendar do
  @moduledoc """
  Pure availability projections for fulfillment calendars.

  `unavailable_reason/3` is the single booking rule; the customer and admin
  cell-state functions project it onto the coarser vocabularies each calendar
  renders. The editor that *writes* these attributes lives in
  `FulfillmentOption.Changes.{ToggleDate, SetWeekday, SetWeek, ResetCalendar}`.
  """

  alias Edenflowers.Fulfillment.FulfillmentOption
  alias Edenflowers.Fulfillment.Weekday

  @type unavailable_reason ::
          :past
          | :date_disabled
          | :weekday_disabled
          | :same_day_delivery_disabled
          | :order_deadline_passed

  @type customer_cell_state :: :open | :closed | :past

  @type admin_cell_state :: :open | :past | :weekday_disabled | :date_disabled

  @doc """
  The booking rule. Returns `nil` when `option` can be fulfilled on `date`,
  otherwise the reason it's blocked. `now` must be a Helsinki-zoned `DateTime`:
  the same-day deadline compares wall-clock time against `order_deadline`,
  which is stored in Helsinki local time.
  """
  @spec unavailable_reason(FulfillmentOption.t(), Date.t(), DateTime.t()) :: unavailable_reason() | nil
  def unavailable_reason(%FulfillmentOption{} = option, %Date{} = date, %DateTime{} = now) do
    today? = Date.compare(date, now) == :eq

    cond do
      Date.compare(date, now) == :lt -> :past
      date in option.disabled_dates -> :date_disabled
      date not in option.enabled_dates and Weekday.from_date(date) not in option.available_days -> :weekday_disabled
      today? and not option.same_day -> :same_day_delivery_disabled
      today? and Time.compare(now, option.order_deadline) == :gt -> :order_deadline_passed
      true -> nil
    end
  end

  @doc """
  Cell state for the customer checkout calendar. A customer can't act on *why*
  a date is unavailable, so every blocked weekday or date reads as `:closed`,
  and a today that's past its deadline collapses to `:past`.
  """
  @spec customer_cell_state(FulfillmentOption.t(), Date.t(), DateTime.t()) :: customer_cell_state()
  def customer_cell_state(%FulfillmentOption{} = option, %Date{} = date, now \\ now()) do
    case unavailable_reason(option, date, now) do
      nil -> :open
      reason when reason in [:date_disabled, :weekday_disabled] -> :closed
      _past_or_same_day -> :past
    end
  end

  @doc """
  Cell state for the admin date-toggle editor. The admin is editing rules, not
  booking against them, so same-day deadlines don't apply and today behaves
  like any other date. `:weekday_disabled` and `:date_disabled` stay distinct
  because clicking each makes a different edit.
  """
  @spec admin_cell_state(FulfillmentOption.t(), Date.t(), Date.t()) :: admin_cell_state()
  def admin_cell_state(%FulfillmentOption{} = option, %Date{} = date, %Date{} = today) do
    cond do
      Date.compare(date, today) == :lt -> :past
      date in option.disabled_dates -> :date_disabled
      date in option.enabled_dates -> :open
      Weekday.from_date(date) in option.available_days -> :open
      true -> :weekday_disabled
    end
  end

  @doc """
  Whether an explicit per-date override (in `enabled_dates` or `disabled_dates`)
  sets the date's state, rather than its weekday rule. Lets the admin calendar
  flag deliberate exceptions.
  """
  @spec override?(FulfillmentOption.t(), Date.t()) :: boolean()
  def override?(%FulfillmentOption{} = option, %Date{} = date) do
    date in option.enabled_dates or date in option.disabled_dates
  end

  defp now, do: DateTime.now!("Europe/Helsinki")
end
