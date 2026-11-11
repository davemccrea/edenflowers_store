defmodule Edenflowers.Fulfillment.Changes.SetWeekdayTest do
  use ExUnit.Case, async: true
  alias Edenflowers.Fulfillment.Changes.SetWeekday
  alias Edenflowers.Fulfillment.ShopCalendar

  describe "set_weekday/3" do
    test "turning a weekday :on prunes stale enabled_dates on that weekday" do
      # Mondays are closed, but an enabled_dates override opens Monday 15 April 2024.
      calendar =
        struct!(
          ShopCalendar,
          available_days: [:tuesday, :wednesday, :thursday, :friday, :saturday, :sunday],
          enabled_dates: [~D[2024-04-15]]
        )

      result = SetWeekday.set_weekday(calendar, :monday, :on)

      assert :monday in result.available_days
      # The opening override is no longer needed because the weekday rule now opens Mondays.
      refute ~D[2024-04-15] in result.enabled_dates
    end

    test "turning a weekday :on preserves disabled_dates on that weekday" do
      # Mondays are closed, so the disabled_dates entry for 15 April is initially redundant.
      # Once Mondays are opened, that entry must remain to keep this particular date closed.
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
      # Mondays are open, but a disabled_dates override closes Monday 15 April 2024.
      calendar =
        struct!(ShopCalendar, disabled_dates: [~D[2024-04-15]])

      result = SetWeekday.set_weekday(calendar, :monday, :off)

      refute :monday in result.available_days
      # The closing override is now redundant because the weekday rule closes Mondays.
      refute ~D[2024-04-15] in result.disabled_dates
    end

    test "turning a weekday :off preserves enabled_dates on that weekday" do
      # Mondays are open, so the enabled_dates entry for 15 April is initially redundant.
      # Once Mondays are closed, that entry must remain to keep this particular date open.
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
      # The weekday rule currently opens Sundays, including Mother's Day.
      calendar = %ShopCalendar{}

      result = SetWeekday.set_weekday(calendar, :sunday, :off)

      refute :sunday in result.available_days
      # Mother's Day must remain open via an enabled override.
      assert ~D[2026-05-10] in result.enabled_dates
    end

    test "set_weekday :on preserves a closed key date by adding a disabled override" do
      # The weekday rule currently closes Sundays, including Mother's Day.
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
