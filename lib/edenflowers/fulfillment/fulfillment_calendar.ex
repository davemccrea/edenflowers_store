defmodule Edenflowers.Fulfillment.FulfillmentCalendar do
  @moduledoc """
  Pure availability projections for fulfillment calendars.

  `unavailable_reason/3` is the single booking rule, shared by the order
  validator (via the `fulfill_on_date` action) and the checkout calendar.
  `customer_cell_state/3` and `admin_cell_state/3` project that rule onto the
  coarser vocabularies each calendar renders, and `override?/2` marks cells set
  by an explicit override rather than the weekday rule.

  The admin date-toggle editor that *writes* these attributes lives next to its
  callers in `FulfillmentOption.Changes.{ToggleDate, SetWeekday, SetWeek, ResetCalendar}`.
  """

  alias Edenflowers.Fulfillment.FulfillmentOption
  alias Edenflowers.Fulfillment.Weekday

  @typedoc """
  Why an option can't be fulfilled on a date, or `nil` when it can. Shared by
  the order validator (via the `fulfill_on_date` action) and the customer
  checkout calendar so both honour exactly the same booking rules.
  """
  @type unavailable_reason ::
          :past
          | :date_disabled
          | :weekday_disabled
          | :same_day_delivery_disabled
          | :order_deadline_passed

  @typedoc """
  Customer-facing calendar cell state. The customer can't act on the why-not,
  so every unavailable date — whether the weekday is off or the date is
  explicitly in `disabled_dates` — reads as `:closed`.
  """
  @type customer_cell_state :: :open | :closed | :past

  @typedoc """
  Admin-facing calendar cell state. The admin is editing the rules, so the
  distinction between `:weekday_disabled` (the weekday rule closes the date)
  and `:date_disabled` (an explicit override closes the date) matters —
  clicking each produces a different update.
  """
  @type admin_cell_state :: :open | :past | :weekday_disabled | :date_disabled

  @doc """
  The booking rule. Returns `nil` when `option` can be fulfilled on `date` at
  `now`, otherwise the reason it's blocked. `now` must be a Helsinki-zoned
  `DateTime`: the same-day deadline compares wall-clock time against
  `order_deadline`, which is stored in Helsinki local time.
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
  Customer-facing cell state for the checkout calendar. `now` defaults to the
  current Helsinki time; same-day deadline rules apply, so today collapses to
  `:past` once the order deadline has passed or when `same_day: false`. From the
  customer's perspective, "can't pick today" looks identical to "the past".
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
  Admin-facing cell state for the date-toggle editor. `today` is a `Date`;
  same-day deadline rules are skipped because the admin is editing rules, not
  booking against them. Today reflects whatever the weekday rule and any
  per-date override say, so it can be toggled like any other date.
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
  Whether the date's state is set by an explicit override rather than its
  weekday rule — i.e. the date appears in `enabled_dates` or `disabled_dates`.
  Used to mark cells that contradict the weekday default so admins can spot
  deliberate exceptions at a glance.
  """
  @spec override?(FulfillmentOption.t(), Date.t()) :: boolean()
  def override?(%FulfillmentOption{} = option, %Date{} = date) do
    date in option.enabled_dates or date in option.disabled_dates
  end

  defp now, do: DateTime.now!("Europe/Helsinki")
end
