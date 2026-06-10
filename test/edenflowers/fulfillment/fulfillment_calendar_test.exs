defmodule Edenflowers.Fulfillment.FulfillmentCalendarTest do
  use Edenflowers.DataCase
  import Generator
  alias Edenflowers.Fulfillment.FulfillmentCalendar

  setup do
    tax_rate = generate(tax_rate())
    [tax_rate_id: tax_rate.id]
  end

  describe "unavailable_reason/3" do
    test ":past when date is in the past", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      now = DateTime.from_naive!(~N[2023-09-15 10:30:00], "Europe/Helsinki")

      assert :past == FulfillmentCalendar.unavailable_reason(option, ~D[2023-09-14], now)
    end

    test ":weekday_disabled when day of week is disabled", %{tax_rate_id: tax_rate_id} do
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
          )
        )

      now = DateTime.from_naive!(~N[2023-09-09 20:15:00], "Europe/Helsinki")

      # 10th Sept 2023 is a Sunday
      assert :weekday_disabled == FulfillmentCalendar.unavailable_reason(option, ~D[2023-09-10], now)
    end

    test ":same_day_delivery_disabled when same day fulfillment is not enabled", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id, same_day: false, order_deadline: ~T[14:00:00]))
      now = DateTime.from_naive!(~N[2023-09-20 09:45:00], "Europe/Helsinki")

      assert :same_day_delivery_disabled == FulfillmentCalendar.unavailable_reason(option, ~D[2023-09-20], now)
    end

    test "nil when same day fulfillment is enabled and before the deadline", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id, same_day: true, order_deadline: ~T[14:00:00]))
      now = DateTime.from_naive!(~N[2023-06-01 13:59:00], "Europe/Helsinki")

      assert nil == FulfillmentCalendar.unavailable_reason(option, ~D[2023-06-01], now)
    end

    test ":order_deadline_passed when same day is enabled but the cutoff has passed", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id, same_day: true, order_deadline: ~T[14:00:00]))
      now = DateTime.from_naive!(~N[2023-06-01 14:01:00], "Europe/Helsinki")

      assert :order_deadline_passed == FulfillmentCalendar.unavailable_reason(option, ~D[2023-06-01], now)
    end

    test ":date_disabled when the date is disabled", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id, disabled_dates: [~D[2023-02-15]]))
      now = DateTime.from_naive!(~N[2023-02-10 12:00:00], "Europe/Helsinki")

      assert :date_disabled == FulfillmentCalendar.unavailable_reason(option, ~D[2023-02-15], now)
    end

    test "an enabled_dates override opens an otherwise-closed weekday", %{tax_rate_id: tax_rate_id} do
      # Disable fulfillment on Sundays except on Sunday 7th April 2024
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id, sunday: false, enabled_dates: [~D[2024-04-07]]))
      now = DateTime.from_naive!(~N[2024-04-06 09:20:00], "Europe/Helsinki")

      assert nil == FulfillmentCalendar.unavailable_reason(option, ~D[2024-04-07], now)
    end

    test "a disabled_dates override closes an otherwise-open weekday", %{tax_rate_id: tax_rate_id} do
      # Enable fulfillment on Wednesdays except on Wednesday 3rd April 2024
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id, wednesday: true, disabled_dates: [~D[2024-04-03]]))
      now = DateTime.from_naive!(~N[2024-04-02 17:50:00], "Europe/Helsinki")

      assert :date_disabled == FulfillmentCalendar.unavailable_reason(option, ~D[2024-04-03], now)
    end
  end

  describe "customer_cell_state/3" do
    test ":open when fulfillable", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      now = DateTime.from_naive!(~N[2024-04-02 09:00:00], "Europe/Helsinki")
      assert :open == FulfillmentCalendar.customer_cell_state(option, ~D[2024-04-05], now)
    end

    test ":past when date is before today", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      now = DateTime.from_naive!(~N[2024-04-02 09:00:00], "Europe/Helsinki")
      assert :past == FulfillmentCalendar.customer_cell_state(option, ~D[2024-04-01], now)
    end

    test ":closed when weekday is disabled and no explicit enable", %{tax_rate_id: tax_rate_id} do
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
          )
        )

      now = DateTime.from_naive!(~N[2024-04-02 09:00:00], "Europe/Helsinki")
      # 2024-04-07 is a Sunday
      assert :closed == FulfillmentCalendar.customer_cell_state(option, ~D[2024-04-07], now)
    end

    test ":closed when date is explicitly disabled", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id, disabled_dates: [~D[2024-04-10]]))
      now = DateTime.from_naive!(~N[2024-04-02 09:00:00], "Europe/Helsinki")
      assert :closed == FulfillmentCalendar.customer_cell_state(option, ~D[2024-04-10], now)
    end

    test ":past when same-day disabled and date is today", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id, same_day: false, order_deadline: ~T[14:00:00]))
      now = DateTime.from_naive!(~N[2024-04-02 09:00:00], "Europe/Helsinki")
      assert :past == FulfillmentCalendar.customer_cell_state(option, ~D[2024-04-02], now)
    end

    test ":past when order deadline has passed", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id, same_day: true, order_deadline: ~T[14:00:00]))
      now = DateTime.from_naive!(~N[2024-04-02 15:00:00], "Europe/Helsinki")
      assert :past == FulfillmentCalendar.customer_cell_state(option, ~D[2024-04-02], now)
    end
  end

  describe "admin_cell_state/3" do
    test ":open when weekday rule allows the date", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      assert :open == FulfillmentCalendar.admin_cell_state(option, ~D[2024-04-05], ~D[2024-04-02])
    end

    test ":past when date is before today", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      assert :past == FulfillmentCalendar.admin_cell_state(option, ~D[2024-04-01], ~D[2024-04-02])
    end

    test ":weekday_disabled when weekday is disabled and no explicit enable", %{tax_rate_id: tax_rate_id} do
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
          )
        )

      # 2024-04-07 is a Sunday
      assert :weekday_disabled == FulfillmentCalendar.admin_cell_state(option, ~D[2024-04-07], ~D[2024-04-02])
    end

    test ":date_disabled when date is explicitly disabled", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id, disabled_dates: [~D[2024-04-10]]))
      assert :date_disabled == FulfillmentCalendar.admin_cell_state(option, ~D[2024-04-10], ~D[2024-04-02])
    end

    test ":open when date is explicitly enabled on an otherwise-closed weekday", %{tax_rate_id: tax_rate_id} do
      # 2024-04-07 is a Sunday
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday],
            enabled_dates: [~D[2024-04-07]]
          )
        )

      assert :open == FulfillmentCalendar.admin_cell_state(option, ~D[2024-04-07], ~D[2024-04-02])
    end

    test "today is not collapsed to :past — same-day rules don't apply to admin", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id, same_day: false, order_deadline: ~T[14:00:00]))
      assert :open == FulfillmentCalendar.admin_cell_state(option, ~D[2024-04-02], ~D[2024-04-02])
    end
  end

  describe "override?/2" do
    test "true when the date is in enabled_dates", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id, enabled_dates: [~D[2024-04-07]]))
      assert FulfillmentCalendar.override?(option, ~D[2024-04-07])
    end

    test "true when the date is in disabled_dates", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id, disabled_dates: [~D[2024-04-10]]))
      assert FulfillmentCalendar.override?(option, ~D[2024-04-10])
    end

    test "false for a date governed only by the weekday rule", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      refute FulfillmentCalendar.override?(option, ~D[2024-04-10])
    end
  end

  describe "toggle_date/2" do
    test "closes a date when its weekday is currently available", %{tax_rate_id: tax_rate_id} do
      # All weekdays available, no overrides
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))

      # 2024-04-10 is a Wednesday
      assert %{enabled_dates: [], disabled_dates: [~D[2024-04-10]]} =
               FulfillmentCalendar.toggle_date(option, ~D[2024-04-10])
    end

    test "opens a date when its weekday is currently disabled", %{tax_rate_id: tax_rate_id} do
      # Sunday off, no overrides
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
          )
        )

      # 2024-04-07 is a Sunday
      assert %{enabled_dates: [~D[2024-04-07]], disabled_dates: []} =
               FulfillmentCalendar.toggle_date(option, ~D[2024-04-07])
    end

    test "removes an existing off-override", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id, disabled_dates: [~D[2024-04-10]]))

      assert %{enabled_dates: [], disabled_dates: []} =
               FulfillmentCalendar.toggle_date(option, ~D[2024-04-10])
    end

    test "removes an existing on-override", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id, enabled_dates: [~D[2024-04-07]]))

      assert %{enabled_dates: [], disabled_dates: []} =
               FulfillmentCalendar.toggle_date(option, ~D[2024-04-07])
    end

    test "off-override does not duplicate other off-overrides", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id, disabled_dates: [~D[2024-04-15]]))

      assert %{disabled_dates: dates} = FulfillmentCalendar.toggle_date(option, ~D[2024-04-10])
      assert ~D[2024-04-15] in dates
      assert ~D[2024-04-10] in dates
    end
  end

  describe "set_weekday/3" do
    test "setting :off removes a currently-available weekday", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      %{available_days: days} = FulfillmentCalendar.set_weekday(option, :sunday, :off)
      refute :sunday in days
    end

    test "setting :on adds a currently-disabled weekday", %{tax_rate_id: tax_rate_id} do
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
          )
        )

      %{available_days: days} = FulfillmentCalendar.set_weekday(option, :sunday, :on)
      assert :sunday in days
    end

    test "is idempotent — :on on an already-on weekday is a no-op", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      %{available_days: days} = FulfillmentCalendar.set_weekday(option, :sunday, :on)
      assert Enum.sort(days) == Enum.sort(option.available_days)
    end

    test "turning a weekday :on prunes stale enabled_dates on that weekday", %{tax_rate_id: tax_rate_id} do
      # 2024-04-15 is a Monday. Start with Mondays off and an on-override.
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:tuesday, :wednesday, :thursday, :friday, :saturday, :sunday],
            enabled_dates: [~D[2024-04-15]]
          )
        )

      result = FulfillmentCalendar.set_weekday(option, :monday, :on)

      assert :monday in result.available_days
      # The on-override is no longer needed — Mondays are open now.
      refute ~D[2024-04-15] in result.enabled_dates
    end

    test "turning a weekday :on preserves disabled_dates on that weekday", %{tax_rate_id: tax_rate_id} do
      # Mondays off, with Mon 2024-04-15 in disabled_dates (redundant but present).
      # After turning Mondays on, the off-override is a genuine exception and must survive.
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:tuesday, :wednesday, :thursday, :friday, :saturday, :sunday],
            disabled_dates: [~D[2024-04-15]]
          )
        )

      result = FulfillmentCalendar.set_weekday(option, :monday, :on)

      assert :monday in result.available_days
      assert ~D[2024-04-15] in result.disabled_dates
    end

    test "turning a weekday :off prunes stale disabled_dates on that weekday", %{tax_rate_id: tax_rate_id} do
      # Mondays on, with Mon 2024-04-15 in disabled_dates as an off-override.
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            disabled_dates: [~D[2024-04-15]]
          )
        )

      result = FulfillmentCalendar.set_weekday(option, :monday, :off)

      refute :monday in result.available_days
      # The off-override is now redundant — Mondays are closed by rule.
      refute ~D[2024-04-15] in result.disabled_dates
    end

    test "turning a weekday :off preserves enabled_dates on that weekday", %{tax_rate_id: tax_rate_id} do
      # Mondays on, with Mon 2024-04-15 in enabled_dates (redundant but present).
      # After turning Mondays off, the on-override is a genuine exception and must survive.
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            enabled_dates: [~D[2024-04-15]]
          )
        )

      result = FulfillmentCalendar.set_weekday(option, :monday, :off)

      refute :monday in result.available_days
      assert ~D[2024-04-15] in result.enabled_dates
    end

    test "only touches overrides matching the targeted weekday", %{tax_rate_id: tax_rate_id} do
      # 2024-04-15 is Monday, 2024-04-16 is Tuesday.
      # Setting Monday off should leave Tuesday's override completely alone.
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            enabled_dates: [~D[2024-04-15]],
            disabled_dates: [~D[2024-04-16]]
          )
        )

      result = FulfillmentCalendar.set_weekday(option, :monday, :off)

      refute :monday in result.available_days
      assert ~D[2024-04-15] in result.enabled_dates
      assert ~D[2024-04-16] in result.disabled_dates
    end
  end

  describe "reset/0" do
    test "returns fully-open weekdays and empty override lists" do
      result = FulfillmentCalendar.reset()
      assert Enum.sort(result.available_days) == [:friday, :monday, :saturday, :sunday, :thursday, :tuesday, :wednesday]
      assert result.enabled_dates == []
      assert result.disabled_dates == []
    end
  end

  describe "key-date protection in smart toggles" do
    # Mother's Day 2026 is a Sunday (~D[2026-05-10]). Father's Day 2026 is also
    # a Sunday (~D[2026-11-08]). Valentine's 2026 is a Saturday (~D[2026-02-14]).

    test "set_weekday :off preserves an open key date by adding an enabled override", %{
      tax_rate_id: tax_rate_id
    } do
      # Sundays currently on. Mother's Day is open by the rule.
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))

      result = FulfillmentCalendar.set_weekday(option, :sunday, :off)

      refute :sunday in result.available_days
      # Mother's Day must remain open via an enabled override.
      assert ~D[2026-05-10] in result.enabled_dates
    end

    test "set_weekday :on preserves a closed key date by adding a disabled override", %{
      tax_rate_id: tax_rate_id
    } do
      # Sundays currently off. Mother's Day is closed by the rule.
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
          )
        )

      result = FulfillmentCalendar.set_weekday(option, :sunday, :on)

      assert :sunday in result.available_days
      # Mother's Day must remain closed via a disabled override.
      assert ~D[2026-05-10] in result.disabled_dates
    end

    test "set_weekday is a no-op for the rule when direction matches current state", %{
      tax_rate_id: tax_rate_id
    } do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      result = FulfillmentCalendar.set_weekday(option, :sunday, :on)

      assert :sunday in result.available_days
      # No protection override should appear since nothing changed.
      refute ~D[2026-05-10] in result.enabled_dates
      refute ~D[2026-05-10] in result.disabled_dates
    end

    test "set_week :closed skips key dates in the week", %{tax_rate_id: tax_rate_id} do
      # All weekdays open. Week containing Mother's Day 2026-05-10 (Sunday).
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      week = Enum.map(0..6, &Date.add(~D[2026-05-04], &1))
      today = ~D[2026-04-01]

      result = FulfillmentCalendar.set_week(option, week, today, :closed)

      # Mon..Sat closed by override; Mother's Day untouched.
      assert ~D[2026-05-04] in result.disabled_dates
      assert ~D[2026-05-09] in result.disabled_dates
      refute ~D[2026-05-10] in result.disabled_dates
      refute ~D[2026-05-10] in result.enabled_dates
    end

    test "set_week :open skips key dates in the week", %{tax_rate_id: tax_rate_id} do
      # Sundays off, so Mother's Day is closed by the rule.
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday],
            disabled_dates: [~D[2026-05-04], ~D[2026-05-05]]
          )
        )

      week = Enum.map(0..6, &Date.add(~D[2026-05-04], &1))
      today = ~D[2026-04-01]

      result = FulfillmentCalendar.set_week(option, week, today, :open)

      # Overrides on the Mon and Tue cleared (rule already opens them).
      refute ~D[2026-05-04] in result.disabled_dates
      refute ~D[2026-05-05] in result.disabled_dates
      # Mother's Day untouched — no enabled_dates entry added to flip it open.
      refute ~D[2026-05-10] in result.enabled_dates
    end
  end

  describe "set_week/4 (without key dates)" do
    test ":closed adds overrides for every open weekday in the week", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      # Mon 2024-04-08 .. Sun 2024-04-14, no key dates in that range.
      week = Enum.map(0..6, &Date.add(~D[2024-04-08], &1))

      result = FulfillmentCalendar.set_week(option, week, ~D[2024-04-01], :closed)

      for date <- week, do: assert(date in result.disabled_dates)
      assert result.enabled_dates == []
    end

    test ":open clears off-overrides without writing redundant on-overrides", %{tax_rate_id: tax_rate_id} do
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            disabled_dates: [~D[2024-04-08], ~D[2024-04-09]]
          )
        )

      week = Enum.map(0..6, &Date.add(~D[2024-04-08], &1))

      result = FulfillmentCalendar.set_week(option, week, ~D[2024-04-01], :open)

      assert result.disabled_dates == []
      # No redundant enabled_dates entries — the weekday rule already opens these.
      assert result.enabled_dates == []
    end

    test "ignores past cells", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      week = Enum.map(0..6, &Date.add(~D[2024-04-08], &1))
      # Today mid-week — only Wed..Sun get overrides.
      today = ~D[2024-04-10]

      result = FulfillmentCalendar.set_week(option, week, today, :closed)

      refute ~D[2024-04-08] in result.disabled_dates
      refute ~D[2024-04-09] in result.disabled_dates
      assert ~D[2024-04-10] in result.disabled_dates
      assert ~D[2024-04-14] in result.disabled_dates
    end
  end
end
