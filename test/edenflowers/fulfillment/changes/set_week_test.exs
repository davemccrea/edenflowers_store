defmodule Edenflowers.Fulfillment.Changes.SetWeekTest do
  use ExUnit.Case, async: true
  alias Edenflowers.Fulfillment.Changes.SetWeek
  alias Edenflowers.Fulfillment.ShopCalendar

  describe "set_week/4" do
    test ":closed adds overrides for every open weekday in the week" do
      calendar = %ShopCalendar{}
      # Mon 2024-04-08 .. Sun 2024-04-14, no key dates in that range.
      week = Enum.map(0..6, &Date.add(~D[2024-04-08], &1))

      result = SetWeek.set_week(calendar, week, ~D[2024-04-01], :closed)

      for date <- week, do: assert(date in result.disabled_dates)
      assert result.enabled_dates == []
    end

    test ":open clears off-overrides without writing redundant on-overrides" do
      calendar =
        struct!(ShopCalendar, disabled_dates: [~D[2024-04-08], ~D[2024-04-09]])

      week = Enum.map(0..6, &Date.add(~D[2024-04-08], &1))

      result = SetWeek.set_week(calendar, week, ~D[2024-04-01], :open)

      assert result.disabled_dates == []
      # No redundant enabled_dates entries — the weekday rule already opens these.
      assert result.enabled_dates == []
    end

    test "ignores past cells" do
      calendar = %ShopCalendar{}
      week = Enum.map(0..6, &Date.add(~D[2024-04-08], &1))
      # Today mid-week — only Wed..Sun get overrides.
      today = ~D[2024-04-10]

      result = SetWeek.set_week(calendar, week, today, :closed)

      refute ~D[2024-04-08] in result.disabled_dates
      refute ~D[2024-04-09] in result.disabled_dates
      assert ~D[2024-04-10] in result.disabled_dates
      assert ~D[2024-04-14] in result.disabled_dates
    end
  end

  describe "key-date protection" do
    # Mother's Day 2026 is a Sunday (~D[2026-05-10]).

    test "set_week :closed skips key dates in the week" do
      # All weekdays open. Week containing Mother's Day 2026-05-10 (Sunday).
      calendar = %ShopCalendar{}
      week = Enum.map(0..6, &Date.add(~D[2026-05-04], &1))
      today = ~D[2026-04-01]

      result = SetWeek.set_week(calendar, week, today, :closed)

      # Mon..Sat closed by override; Mother's Day untouched.
      assert ~D[2026-05-04] in result.disabled_dates
      assert ~D[2026-05-09] in result.disabled_dates
      refute ~D[2026-05-10] in result.disabled_dates
      refute ~D[2026-05-10] in result.enabled_dates
    end

    test "set_week :open skips key dates in the week" do
      # Sundays off, so Mother's Day is closed by the rule.
      calendar =
        struct!(
          ShopCalendar,
          available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday],
          disabled_dates: [~D[2026-05-04], ~D[2026-05-05]]
        )

      week = Enum.map(0..6, &Date.add(~D[2026-05-04], &1))
      today = ~D[2026-04-01]

      result = SetWeek.set_week(calendar, week, today, :open)

      # Overrides on the Mon and Tue cleared (rule already opens them).
      refute ~D[2026-05-04] in result.disabled_dates
      refute ~D[2026-05-05] in result.disabled_dates
      # Mother's Day untouched — no enabled_dates entry added to flip it open.
      refute ~D[2026-05-10] in result.enabled_dates
    end
  end
end
