defmodule Edenflowers.Fulfillment.Availability do
  @moduledoc """
  Pure availability projections of the shop calendar.

  `unavailable_reason/3` is the single booking rule; the customer and admin
  cell-state functions project it onto the coarser vocabularies each calendar
  renders. The editor that *writes* these attributes lives in
  `Changes.{ToggleDate, SetWeekday, SetWeek}` and the
  `:reset_calendar` action.
  """

  alias Edenflowers.Fulfillment.ShopCalendar
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
  The booking rule. Returns `nil` when `calendar` can be fulfilled on `date`,
  otherwise the reason it's blocked. `now` must be a Helsinki-zoned `DateTime`:
  the same-day deadline compares wall-clock time against `order_deadline`,
  which is stored in Helsinki local time.
  """
  @spec unavailable_reason(ShopCalendar.t(), Date.t(), DateTime.t()) :: unavailable_reason() | nil
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def unavailable_reason(%ShopCalendar{} = calendar, %Date{} = date, %DateTime{} = now) do
    today? = Date.compare(date, now) == :eq

    cond do
      Date.compare(date, now) == :lt -> :past
      date in calendar.disabled_dates -> :date_disabled
      date not in calendar.enabled_dates and Weekday.from_date(date) not in calendar.available_days -> :weekday_disabled
      today? and not calendar.same_day -> :same_day_delivery_disabled
      today? and Time.compare(now, calendar.order_deadline) == :gt -> :order_deadline_passed
      true -> nil
    end
  end

  @doc """
  The first date an order placed at `now` could be fulfilled, or nil when the
  shop is closed for the next 60 days.
  """
  @spec next_open_date(ShopCalendar.t(), DateTime.t()) :: Date.t() | nil
  def next_open_date(%ShopCalendar{} = calendar, %DateTime{} = now) do
    now
    |> DateTime.to_date()
    |> Stream.iterate(&Date.add(&1, 1))
    |> Enum.take(60)
    |> Enum.find(&is_nil(unavailable_reason(calendar, &1, now)))
  end

  @doc """
  Cell state for the customer checkout calendar. A customer can't act on *why*
  a date is unavailable, so every blocked weekday or date reads as `:closed`,
  and a today that's past its deadline collapses to `:past`.
  """
  @spec customer_cell_state(ShopCalendar.t(), Date.t(), DateTime.t()) :: customer_cell_state()
  def customer_cell_state(%ShopCalendar{} = calendar, %Date{} = date, now \\ Edenflowers.ShopTime.now()) do
    case unavailable_reason(calendar, date, now) do
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
  @spec admin_cell_state(ShopCalendar.t(), Date.t(), Date.t()) :: admin_cell_state()
  def admin_cell_state(%ShopCalendar{} = calendar, %Date{} = date, %Date{} = today) do
    cond do
      Date.compare(date, today) == :lt -> :past
      date in calendar.disabled_dates -> :date_disabled
      date in calendar.enabled_dates -> :open
      Weekday.from_date(date) in calendar.available_days -> :open
      true -> :weekday_disabled
    end
  end

  @doc """
  Whether an explicit per-date override (in `enabled_dates` or `disabled_dates`)
  sets the date's state, rather than its weekday rule. Lets the admin calendar
  flag deliberate exceptions.
  """
  @spec override?(ShopCalendar.t(), Date.t()) :: boolean()
  def override?(%ShopCalendar{} = calendar, %Date{} = date) do
    date in calendar.enabled_dates or date in calendar.disabled_dates
  end
end
