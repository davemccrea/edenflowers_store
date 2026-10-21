defmodule Edenflowers.Fulfillment.Changes.SetWeekdayTest do
  use ExUnit.Case, async: true
  alias Edenflowers.Fulfillment.Changes.SetWeekday
  alias Edenflowers.Fulfillment.ShopCalendar

  describe "set_weekday/3" do
    test "turning a weekday :on prunes stale enabled_dates on that weekday" do
      # 2024-04-15 is a Monday. Start with Mondays off and an on-override.
      calendar =
        struct!(
          ShopCalendar,
          available_days: [:tuesday, :wednesday, :thursday, :friday, :saturday, :sunday],
          enabled_dates: [~D[2024-04-15]]
        )

      result = SetWeekday.set_weekday(calendar, :monday, :on)

      assert :monday in result.available_days
      # The on-override is no longer needed — Mondays are open now.
      refute ~D[2024-04-15] in result.enabled_dates
    end

    test "turning a weekday :on preserves disabled_dates on that weekday" do
      # Mondays off, with Mon 2024-04-15 in disabled_dates (redundant but present).
      # After turning Mondays on, the off-override is a genuine exception and must survive.
      calendar =
        struct!(
          ShopCalendar,
          available_days: [:tuesday, :wednesday, :thursday, :friday, :saturday, :sunday],
          disabled_dates: [~D[2024-04-15]]
        )

      result = SetWeekday.set_weekday(calendar, :monday, :on)

      assert :monday in result.available_days
      assert ~D[2024-04-15] in result.disabled_dates
    end

    test "turning a weekday :off prunes stale disabled_dates on that weekday" do
      # Mondays on, with Mon 2024-04-15 in disabled_dates as an off-override.
      calendar =
        struct!(ShopCalendar, disabled_dates: [~D[2024-04-15]])

      result = SetWeekday.set_weekday(calendar, :monday, :off)

      refute :monday in result.available_days
      # The off-override is now redundant — Mondays are closed by rule.
      refute ~D[2024-04-15] in result.disabled_dates
    end

    test "turning a weekday :off preserves enabled_dates on that weekday" do
      # Mondays on, with Mon 2024-04-15 in enabled_dates (redundant but present).
      # After turning Mondays off, the on-override is a genuine exception and must survive.
      calendar =
        struct!(ShopCalendar, enabled_dates: [~D[2024-04-15]])

      result = SetWeekday.set_weekday(calendar, :monday, :off)

      refute :monday in result.available_days
      assert ~D[2024-04-15] in result.enabled_dates
    end

    test "only touches overrides matching the targeted weekday" do
      # 2024-04-15 is Monday, 2024-04-16 is Tuesday.
      # Setting Monday off should leave Tuesday's override completely alone.
      calendar =
        struct!(
          ShopCalendar,
          enabled_dates: [~D[2024-04-15]],
          disabled_dates: [~D[2024-04-16]]
        )

      result = SetWeekday.set_weekday(calendar, :monday, :off)

      refute :monday in result.available_days
      assert ~D[2024-04-15] in result.enabled_dates
      assert ~D[2024-04-16] in result.disabled_dates
    end
  end

  describe "key-date protection" do
    # Mother's Day 2026 is a Sunday (~D[2026-05-10]).

    test "set_weekday :off preserves an open key date by adding an enabled override" do
      # Sundays currently on. Mother's Day is open by the rule.
      calendar = %ShopCalendar{}

      result = SetWeekday.set_weekday(calendar, :sunday, :off)

      refute :sunday in result.available_days
      # Mother's Day must remain open via an enabled override.
      assert ~D[2026-05-10] in result.enabled_dates
    end

    test "set_weekday :on preserves a closed key date by adding a disabled override" do
      # Sundays currently off. Mother's Day is closed by the rule.
      calendar =
        struct!(ShopCalendar, available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday])

      result = SetWeekday.set_weekday(calendar, :sunday, :on)

      assert :sunday in result.available_days
      # Mother's Day must remain closed via a disabled override.
      assert ~D[2026-05-10] in result.disabled_dates
    end

    test "turning an already-on weekday :on changes nothing, key dates included" do
      calendar = %ShopCalendar{}

      assert SetWeekday.set_weekday(calendar, :sunday, :on) ==
               Map.take(calendar, [:available_days, :enabled_dates, :disabled_dates])
    end
  end
end
