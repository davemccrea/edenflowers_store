defmodule Edenflowers.Fulfillment.FulfillmentCalendar do
  @moduledoc """
  Pure calendar logic for fulfillment availability.

  Two responsibilities:

    * **Availability projections** — `unavailable_reason/3` is the single
      booking rule, shared by the order validator (via the `fulfill_on_date`
      action) and the checkout calendar. `customer_cell_state/3` and
      `admin_cell_state/3` project that rule onto the coarser vocabularies each
      calendar renders.

    * **The admin date-toggle editor** — `toggle_date/2`, `set_weekday/3`,
      `set_week/4` and `reset/0` translate calendar clicks into updated
      attribute maps that the LiveView hands to `Ash.update/2`, keeping click
      semantics out of the socket so they can be unit-tested without a database.

  ## Click semantics

  - Clicking a **weekday header** toggles that weekday in `available_days`.
    This is the default rule for that weekday.

  - Clicking a **date cell** toggles an *override*:
    - If the date's weekday is currently available, the click adds the date
      to `disabled_dates` (closes that specific date).
    - If the date's weekday is currently unavailable, the click adds it to
      `enabled_dates` (opens that specific date).
    - Clicking an already-overridden date removes the override, returning
      the date to its weekday default.

  This means every click is reversible and the data shape stays minimal:
  no override is stored once a date matches its weekday default.
  """

  alias Edenflowers.Fulfillment.{FulfillmentOption, KeyDates}
  alias Edenflowers.Fulfillment.Weekday

  @weekdays [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday, :sunday]

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

  @doc """
  Toggle a date for a single fulfillment option, returning the updated
  `%{enabled_dates: [...], disabled_dates: [...]}` map. Pass these to
  `Ash.update/2` to persist.

  See module doc for the click semantics.
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

      weekday_available?(option, date) ->
        %{enabled_dates: enabled, disabled_dates: [date | disabled]}

      true ->
        %{enabled_dates: [date | enabled], disabled_dates: disabled}
    end
  end

  @doc """
  Set a weekday's rule for a single option to the given direction, returning
  the updated `%{available_days: [...], enabled_dates: [...], disabled_dates: [...]}`
  map. Idempotent — already-matching options pass through unchanged.

  Prunes any now-redundant overrides whose direction matches the new weekday
  rule: an `enabled_dates` entry on a now-available weekday is dropped (the
  rule already opens that date), and a `disabled_dates` entry on a now-closed
  weekday is dropped (the rule already closes it). This keeps the invariant
  "every override genuinely contradicts the weekday rule" so the override
  mark in the UI never lies.
  """
  @spec set_weekday(FulfillmentOption.t(), Weekday.t(), :on | :off) :: %{
          available_days: [Weekday.t()],
          enabled_dates: [Date.t()],
          disabled_dates: [Date.t()]
        }
  def set_weekday(%FulfillmentOption{} = option, weekday, direction)
      when weekday in @weekdays and direction in [:on, :off] do
    currently_available? = weekday in option.available_days

    available =
      case {direction, currently_available?} do
        {:on, false} -> [weekday | option.available_days]
        {:off, true} -> List.delete(option.available_days, weekday)
        _no_change -> option.available_days
      end

    enabled = Enum.reject(option.enabled_dates, &(Weekday.from_date(&1) in available))
    disabled = Enum.reject(option.disabled_dates, &(Weekday.from_date(&1) not in available))

    %{available_days: available, enabled_dates: enabled, disabled_dates: disabled}
    |> preserve_key_dates_on_weekday(option, weekday)
  end

  # After a weekday rule change, any key dates on that weekday whose open/closed
  # state would flip get an override restoring their pre-toggle state. Key dates
  # are never collaterally moved by a smart toggle — the florist has to click
  # them individually.
  defp preserve_key_dates_on_weekday(new_attrs, original_option, weekday) do
    virtual_option = struct(original_option, new_attrs)

    weekday
    |> KeyDates.dates_for_weekday()
    |> Enum.reduce(new_attrs, fn date, attrs ->
      old_open? = open?(original_option, date)
      new_open? = open?(virtual_option, date)

      if old_open? == new_open?, do: attrs, else: restore(attrs, date, old_open?)
    end)
  end

  # Past-agnostic openness — would the rule + overrides leave this date open?
  defp open?(option, date) do
    cond do
      date in option.disabled_dates -> false
      date in option.enabled_dates -> true
      true -> Weekday.from_date(date) in option.available_days
    end
  end

  defp restore(attrs, date, _was_open? = true) do
    %{
      attrs
      | enabled_dates: Enum.uniq([date | attrs.enabled_dates]),
        disabled_dates: List.delete(attrs.disabled_dates, date)
    }
  end

  defp restore(attrs, date, _was_open? = false) do
    %{
      attrs
      | disabled_dates: Enum.uniq([date | attrs.disabled_dates]),
        enabled_dates: List.delete(attrs.enabled_dates, date)
    }
  end

  @doc """
  Set every non-past date in `week` to the given direction for a single
  option, returning the updated `%{enabled_dates: [...], disabled_dates: [...]}`
  map. Idempotent per-date: cells already in the target direction pass
  through unchanged.

  Each per-date flip uses the same minimal-override discipline as
  `toggle_date/2`: a redundant override (matching the weekday rule) is never
  written.
  """
  @spec set_week(FulfillmentOption.t(), [Date.t()], Date.t(), :open | :closed) :: %{
          enabled_dates: [Date.t()],
          disabled_dates: [Date.t()]
        }
  def set_week(%FulfillmentOption{} = option, week, %Date{} = today, direction)
      when is_list(week) and direction in [:open, :closed] do
    initial = %{enabled_dates: option.enabled_dates, disabled_dates: option.disabled_dates}

    week
    |> Enum.reject(&(Date.compare(&1, today) == :lt))
    |> Enum.reject(&KeyDates.key_date?/1)
    |> Enum.reduce(initial, fn date, acc -> set_date(option, acc, date, direction) end)
  end

  # Move a single date to the target direction in the given enabled/disabled
  # accumulator, without writing a redundant override.
  defp set_date(option, %{enabled_dates: enabled, disabled_dates: disabled}, date, :open) do
    cond do
      weekday_available?(option, date) ->
        %{enabled_dates: List.delete(enabled, date), disabled_dates: List.delete(disabled, date)}

      date in enabled ->
        %{enabled_dates: enabled, disabled_dates: List.delete(disabled, date)}

      true ->
        %{enabled_dates: [date | enabled], disabled_dates: List.delete(disabled, date)}
    end
  end

  defp set_date(option, %{enabled_dates: enabled, disabled_dates: disabled}, date, :closed) do
    cond do
      not weekday_available?(option, date) ->
        %{enabled_dates: List.delete(enabled, date), disabled_dates: List.delete(disabled, date)}

      date in disabled ->
        %{enabled_dates: List.delete(enabled, date), disabled_dates: disabled}

      true ->
        %{enabled_dates: List.delete(enabled, date), disabled_dates: [date | disabled]}
    end
  end

  defp weekday_available?(option, date) do
    Weekday.from_date(date) in option.available_days
  end

  @doc """
  Reset attributes for a full-wipe gesture: every weekday open, no overrides.

  Independent of the option's current state — this is a confirmed-destructive
  reset, not a toggle. Key-date protection deliberately does not apply: the
  florist has explicitly asked for everything to clear.
  """
  @spec reset() :: %{
          available_days: [Weekday.t()],
          enabled_dates: [Date.t()],
          disabled_dates: [Date.t()]
        }
  def reset do
    %{available_days: @weekdays, enabled_dates: [], disabled_dates: []}
  end

  defp now, do: DateTime.now!("Europe/Helsinki")
end
