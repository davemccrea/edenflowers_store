defmodule Edenflowers.Fulfillment.FulfillmentCalendarTest do
  use Edenflowers.DataCase
  import Generator
  alias Edenflowers.Fulfillment.FulfillmentCalendar
  alias Edenflowers.Weekday

  setup do
    tax_rate = generate(tax_rate())
    [tax_rate_id: tax_rate.id]
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

    test "week_state ignores key dates so a key-date-only week reports as :all_past", %{
      tax_rate_id: tax_rate_id
    } do
      # A week where the only non-past cell is Mother's Day. The button must
      # not look actionable, since the click would no-op anyway.
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      week = Enum.map(0..6, &Date.add(~D[2026-05-04], &1))
      # "today" makes Mon..Sat all past, leaving only Sun (Mother's Day) actionable.
      today = ~D[2026-05-10]

      assert :all_past == FulfillmentCalendar.week_state(option, week, today)
    end
  end

  describe "cell_state_for_options/3" do
    test "returns the single shared state when all options agree", %{tax_rate_id: tax_rate_id} do
      a = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      b = generate(fulfillment_option(tax_rate_id: tax_rate_id))

      today = ~D[2024-04-01]
      future_wednesday = today |> Date.shift(month: 3) |> next_weekday(:wednesday)

      assert :open == FulfillmentCalendar.cell_state_for_options([a, b], future_wednesday, today)
    end

    test "returns :mixed when options disagree", %{tax_rate_id: tax_rate_id} do
      open_option = generate(fulfillment_option(tax_rate_id: tax_rate_id))

      closed_option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
          )
        )

      today = ~D[2024-04-01]
      future_sunday = today |> Date.shift(month: 3) |> next_weekday(:sunday)

      assert :mixed ==
               FulfillmentCalendar.cell_state_for_options(
                 [open_option, closed_option],
                 future_sunday,
                 today
               )
    end

    test "returns :open for an empty options list", %{tax_rate_id: _} do
      assert :open == FulfillmentCalendar.cell_state_for_options([], ~D[2024-04-10], ~D[2024-04-01])
    end
  end

  describe "cell_state_for_scope/4" do
    test ":all aggregates across options", %{tax_rate_id: tax_rate_id} do
      open_option = generate(fulfillment_option(tax_rate_id: tax_rate_id))

      closed_option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
          )
        )

      today = ~D[2024-04-01]
      future_sunday = today |> Date.shift(month: 3) |> next_weekday(:sunday)

      assert :mixed ==
               FulfillmentCalendar.cell_state_for_scope(
                 :all,
                 [open_option, closed_option],
                 future_sunday,
                 today
               )
    end

    test "single-option scope returns that option's admin cell state", %{tax_rate_id: tax_rate_id} do
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
          )
        )

      today = ~D[2024-04-01]
      future_sunday = today |> Date.shift(month: 3) |> next_weekday(:sunday)

      assert :weekday_disabled ==
               FulfillmentCalendar.cell_state_for_scope(option.id, [option], future_sunday, today)
    end

    test "falls back to :open when the scoped option id is unknown", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))

      assert :open ==
               FulfillmentCalendar.cell_state_for_scope("missing-id", [option], ~D[2024-04-10], ~D[2024-04-01])
    end
  end

  describe "scoped_options/2" do
    test ":all returns every option", %{tax_rate_id: tax_rate_id} do
      a = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      b = generate(fulfillment_option(tax_rate_id: tax_rate_id))

      assert [a, b] == FulfillmentCalendar.scoped_options(:all, [a, b])
    end

    test "an id scope filters to that option", %{tax_rate_id: tax_rate_id} do
      a = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      b = generate(fulfillment_option(tax_rate_id: tax_rate_id))

      assert [b] == FulfillmentCalendar.scoped_options(b.id, [a, b])
    end

    test "an unknown id returns an empty list", %{tax_rate_id: tax_rate_id} do
      a = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      assert [] == FulfillmentCalendar.scoped_options("missing-id", [a])
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

  describe "weekday_state/3" do
    test ":all returns :on when every option has the weekday available", %{tax_rate_id: tax_rate_id} do
      a = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      b = generate(fulfillment_option(tax_rate_id: tax_rate_id))

      assert :on == FulfillmentCalendar.weekday_state(:all, [a, b], :monday)
    end

    test ":all returns :off when no option has the weekday available", %{tax_rate_id: tax_rate_id} do
      days = [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
      a = generate(fulfillment_option(tax_rate_id: tax_rate_id, available_days: days))
      b = generate(fulfillment_option(tax_rate_id: tax_rate_id, available_days: days))

      assert :off == FulfillmentCalendar.weekday_state(:all, [a, b], :sunday)
    end

    test ":all returns :mixed when options disagree", %{tax_rate_id: tax_rate_id} do
      a = generate(fulfillment_option(tax_rate_id: tax_rate_id))

      b =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
          )
        )

      assert :mixed == FulfillmentCalendar.weekday_state(:all, [a, b], :sunday)
    end

    test ":all returns :on for an empty options list" do
      # Regression: with no options, the page renders a default `:on` header.
      # Returning :mixed here previously made empty pages render with a "varies"
      # treatment despite there being nothing to vary.
      assert :on == FulfillmentCalendar.weekday_state(:all, [], :sunday)
    end

    test "single-option scope reads off that option", %{tax_rate_id: tax_rate_id} do
      a = generate(fulfillment_option(tax_rate_id: tax_rate_id))

      b =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
          )
        )

      assert :on == FulfillmentCalendar.weekday_state(a.id, [a, b], :sunday)
      assert :off == FulfillmentCalendar.weekday_state(b.id, [a, b], :sunday)
    end

    test "single-option scope falls back to :on when the id is unknown", %{tax_rate_id: tax_rate_id} do
      a = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      assert :on == FulfillmentCalendar.weekday_state("missing-id", [a], :sunday)
    end
  end

  describe "weekday_toggle_direction/2" do
    test "returns :off when any option has the weekday on", %{tax_rate_id: tax_rate_id} do
      a = generate(fulfillment_option(tax_rate_id: tax_rate_id))

      b =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
          )
        )

      assert :off == FulfillmentCalendar.weekday_toggle_direction([a, b], :sunday)
    end

    test "returns :on when no option has the weekday on", %{tax_rate_id: tax_rate_id} do
      days = [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
      a = generate(fulfillment_option(tax_rate_id: tax_rate_id, available_days: days))
      b = generate(fulfillment_option(tax_rate_id: tax_rate_id, available_days: days))

      assert :on == FulfillmentCalendar.weekday_toggle_direction([a, b], :sunday)
    end
  end

  describe "week_state/3 (without key dates)" do
    test ":all_open when every actionable cell is open", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      # 2024-04-08 Mon .. 2024-04-14 Sun — a Mon-Sun week with no key dates.
      week = Enum.map(0..6, &Date.add(~D[2024-04-08], &1))
      assert :all_open == FulfillmentCalendar.week_state(option, week, ~D[2024-04-01])
    end

    test ":all_closed when every actionable cell is closed", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id, available_days: []))
      week = Enum.map(0..6, &Date.add(~D[2024-04-08], &1))
      assert :all_closed == FulfillmentCalendar.week_state(option, week, ~D[2024-04-01])
    end

    test ":mixed when some cells are open and some closed", %{tax_rate_id: tax_rate_id} do
      # Closed on Sunday only.
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
          )
        )

      week = Enum.map(0..6, &Date.add(~D[2024-04-08], &1))
      assert :mixed == FulfillmentCalendar.week_state(option, week, ~D[2024-04-01])
    end

    test ":all_past when every cell is before today", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      week = Enum.map(0..6, &Date.add(~D[2024-04-08], &1))
      assert :all_past == FulfillmentCalendar.week_state(option, week, ~D[2024-04-15])
    end
  end

  describe "week_toggle_direction/3" do
    test "returns nil when no option has any actionable cell", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      week = Enum.map(0..6, &Date.add(~D[2024-04-08], &1))
      # Today after the week → every cell is past.
      assert nil == FulfillmentCalendar.week_toggle_direction([option], week, ~D[2024-04-15])
    end

    test "returns :closed when any option has open or mixed cells", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      week = Enum.map(0..6, &Date.add(~D[2024-04-08], &1))
      assert :closed == FulfillmentCalendar.week_toggle_direction([option], week, ~D[2024-04-01])
    end

    test "returns :open when every option's week is fully closed", %{tax_rate_id: tax_rate_id} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate_id, available_days: []))
      week = Enum.map(0..6, &Date.add(~D[2024-04-08], &1))
      assert :open == FulfillmentCalendar.week_toggle_direction([option], week, ~D[2024-04-01])
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

  defp next_weekday(date, weekday) do
    target = Weekday.to_integer(weekday)

    Stream.iterate(date, &Date.add(&1, 1))
    |> Enum.find(&(Date.day_of_week(&1) == target))
  end
end
