defmodule Edenflowers.Fulfillment.Availability do
  @moduledoc """
  Pure availability projections of the shop calendar.

  `unavailable_reason/3` is the single booking rule; the customer and admin
  cell-state functions project it onto the coarser vocabularies each calendar
  renders. The editor that *writes* these attributes lives in
  `Changes.{ToggleDate, SetWeekday, SetWeek}` and the
  `:reset_calendar` action.
  """

  alias Edenflowers.Fulfillment.KeyDates
  alias Edenflowers.Fulfillment.ShopCalendar
  alias Edenflowers.Fulfillment.Weekday

  @type unavailable_reason ::
          :past
          | :date_disabled
          | :weekday_disabled
          | :same_day_delivery_disabled
          | :order_deadline_passed
          | :before_available_from

  @type customer_cell_state :: :open | :closed | :past

  @type admin_cell_state :: :open | :past | :weekday_disabled | :date_disabled

  @doc """
  The booking rule. Returns `nil` when `calendar` can be fulfilled on `date`,
  otherwise the reason it's blocked. `now` must be a Helsinki-zoned `DateTime`:
  the same-day deadline compares wall-clock time against `order_deadline`,
  which is stored in Helsinki local time. `available_from` is an order's
  Available from, the first day its flowers let Jennie make it, or nil.
  """
  @spec unavailable_reason(ShopCalendar.t(), Date.t(), DateTime.t(), Date.t() | nil) :: unavailable_reason() | nil
  # credo:disable-for-next-line /Complexity/
  def unavailable_reason(%ShopCalendar{} = calendar, %Date{} = date, %DateTime{} = now, available_from \\ nil) do
    today? = Date.compare(date, now) == :eq

    cond do
      Date.compare(date, now) == :lt -> :past
      available_from && Date.compare(date, available_from) == :lt -> :before_available_from
      date in calendar.disabled_dates -> :date_disabled
      date not in calendar.enabled_dates and not open_by_rule?(calendar, date) -> :weekday_disabled
      today? and not calendar.same_day -> :same_day_delivery_disabled
      today? and Time.compare(now, calendar.order_deadline) == :gt -> :order_deadline_passed
      true -> nil
    end
  end

  @doc """
  Searches 60 dates starting at `from`, or the date in `now` when `from` is nil.
  Returns the first available date, or nil when none is available.
  Use `from` for orders needing preparation time, such as a Gift voucher card.
  """
  @spec next_open_date(ShopCalendar.t(), DateTime.t(), Date.t() | nil) :: Date.t() | nil
  def next_open_date(%ShopCalendar{} = calendar, %DateTime{} = now, from \\ nil) do
    (from || DateTime.to_date(now))
    |> Stream.iterate(&Date.add(&1, 1))
    |> Enum.take(60)
    |> Enum.find(&is_nil(unavailable_reason(calendar, &1, now)))
  end

  @doc """
  What the storefront bar tells a customer ordering at `now`: `{:order_today, deadline}`
  while an order can still go out today, otherwise `{:next_open, date}`, or nil when
  nothing opens in the next 60 days. A holiday reads as a later next date, not as
  "closed": customers can still order then, for when Jennie is back.
  """
  @spec order_status(ShopCalendar.t(), DateTime.t()) :: {:order_today, Time.t()} | {:next_open, Date.t()} | nil
  def order_status(%ShopCalendar{} = calendar, %DateTime{} = now) do
    today = DateTime.to_date(now)

    case next_open_date(calendar, now) do
      nil -> nil
      ^today -> {:order_today, calendar.order_deadline}
      date -> {:next_open, date}
    end
  end

  @doc """
  What Jennie can do about orders for today: stop them while customers can
  still book it (`:open`), reopen it when she closed just today (`:closed`), or
  nothing, when the weekday rule, same-day setting or deadline already shut it.
  """
  @spec today_toggle_state(ShopCalendar.t(), DateTime.t()) :: :open | :closed | nil
  def today_toggle_state(%ShopCalendar{} = calendar, now \\ Edenflowers.ShopTime.now()) do
    today = DateTime.to_date(now)

    cond do
      today in calendar.disabled_dates -> :closed
      is_nil(unavailable_reason(calendar, today, now)) -> :open
      true -> nil
    end
  end

  @doc """
  Cell state for the customer checkout calendar. A customer can't act on *why*
  a date is unavailable, so every blocked weekday or date, and every day before
  the order's `available_from`, reads as `:closed`, and a today that's past its
  deadline collapses to `:past`.
  """
  @spec customer_cell_state(ShopCalendar.t(), Date.t(), DateTime.t(), Date.t() | nil) :: customer_cell_state()
  def customer_cell_state(
        %ShopCalendar{} = calendar,
        %Date{} = date,
        now \\ Edenflowers.ShopTime.now(),
        available_from \\ nil
      ) do
    case unavailable_reason(calendar, date, now, available_from) do
      nil -> :open
      reason when reason in [:date_disabled, :weekday_disabled, :before_available_from] -> :closed
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
      open_by_rule?(calendar, date) -> :open
      true -> :weekday_disabled
    end
  end

  @doc """
  Whether `date` is open before any date override: its weekday is open, or it
  is a florist key date. A key date stays open on a closed weekday until Jennie
  closes that date herself, so one added later or in a later year needs no
  override written for it.
  """
  @spec open_by_rule?(ShopCalendar.t(), Date.t()) :: boolean()
  def open_by_rule?(%ShopCalendar{} = calendar, %Date{} = date) do
    Weekday.from_date(date) in calendar.available_days or KeyDates.key_date?(date)
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
