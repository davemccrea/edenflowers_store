defmodule Edenflowers.Fulfillment.AvailabilityTest do
  use Edenflowers.DataCase, async: true
  import Generator
  alias Edenflowers.Fulfillment.Availability

  describe "unavailable_reason/3" do
    test ":past when date is in the past" do
      calendar = shop_calendar()
      now = DateTime.from_naive!(~N[2023-09-15 10:30:00], "Europe/Helsinki")

      assert :past == Availability.unavailable_reason(calendar, ~D[2023-09-14], now)
    end

    test ":weekday_disabled when day of week is disabled" do
      calendar =
        shop_calendar(available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday])

      now = DateTime.from_naive!(~N[2023-09-09 20:15:00], "Europe/Helsinki")

      # 10th Sept 2023 is a Sunday
      assert :weekday_disabled == Availability.unavailable_reason(calendar, ~D[2023-09-10], now)
    end

    test ":same_day_delivery_disabled when same day fulfillment is not enabled" do
      calendar = shop_calendar(same_day: false, order_deadline: ~T[14:00:00])
      now = DateTime.from_naive!(~N[2023-09-20 09:45:00], "Europe/Helsinki")

      assert :same_day_delivery_disabled == Availability.unavailable_reason(calendar, ~D[2023-09-20], now)
    end

    test "nil when same day fulfillment is enabled and before the deadline" do
      calendar = shop_calendar(same_day: true, order_deadline: ~T[14:00:00])
      now = DateTime.from_naive!(~N[2023-06-01 13:59:00], "Europe/Helsinki")

      assert nil == Availability.unavailable_reason(calendar, ~D[2023-06-01], now)
    end

    test ":order_deadline_passed when same day is enabled but the cutoff has passed" do
      calendar = shop_calendar(same_day: true, order_deadline: ~T[14:00:00])
      now = DateTime.from_naive!(~N[2023-06-01 14:01:00], "Europe/Helsinki")

      assert :order_deadline_passed == Availability.unavailable_reason(calendar, ~D[2023-06-01], now)
    end

    test ":date_disabled when the date is disabled" do
      calendar = shop_calendar(disabled_dates: [~D[2023-02-15]])
      now = DateTime.from_naive!(~N[2023-02-10 12:00:00], "Europe/Helsinki")

      assert :date_disabled == Availability.unavailable_reason(calendar, ~D[2023-02-15], now)
    end

    test "an enabled_dates override opens an otherwise-closed weekday" do
      # Disable fulfillment on Sundays except on Sunday 7th April 2024
      calendar = shop_calendar(enabled_dates: [~D[2024-04-07]])
      now = DateTime.from_naive!(~N[2024-04-06 09:20:00], "Europe/Helsinki")

      assert nil == Availability.unavailable_reason(calendar, ~D[2024-04-07], now)
    end

    test "a disabled_dates override closes an otherwise-open weekday" do
      # Enable fulfillment on Wednesdays except on Wednesday 3rd April 2024
      calendar = shop_calendar(disabled_dates: [~D[2024-04-03]])
      now = DateTime.from_naive!(~N[2024-04-02 17:50:00], "Europe/Helsinki")

      assert :date_disabled == Availability.unavailable_reason(calendar, ~D[2024-04-03], now)
    end
  end

  describe "customer_cell_state/3" do
    test ":open when fulfillable" do
      calendar = shop_calendar()
      now = DateTime.from_naive!(~N[2024-04-02 09:00:00], "Europe/Helsinki")
      assert :open == Availability.customer_cell_state(calendar, ~D[2024-04-05], now)
    end

    test ":past when date is before today" do
      calendar = shop_calendar()
      now = DateTime.from_naive!(~N[2024-04-02 09:00:00], "Europe/Helsinki")
      assert :past == Availability.customer_cell_state(calendar, ~D[2024-04-01], now)
    end

    test ":closed when weekday is disabled and no explicit enable" do
      calendar =
        shop_calendar(available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday])

      now = DateTime.from_naive!(~N[2024-04-02 09:00:00], "Europe/Helsinki")
      # 2024-04-07 is a Sunday
      assert :closed == Availability.customer_cell_state(calendar, ~D[2024-04-07], now)
    end

    test ":closed when date is explicitly disabled" do
      calendar = shop_calendar(disabled_dates: [~D[2024-04-10]])
      now = DateTime.from_naive!(~N[2024-04-02 09:00:00], "Europe/Helsinki")
      assert :closed == Availability.customer_cell_state(calendar, ~D[2024-04-10], now)
    end

    test ":past when same-day disabled and date is today" do
      calendar = shop_calendar(same_day: false, order_deadline: ~T[14:00:00])
      now = DateTime.from_naive!(~N[2024-04-02 09:00:00], "Europe/Helsinki")
      assert :past == Availability.customer_cell_state(calendar, ~D[2024-04-02], now)
    end

    test ":past when order deadline has passed" do
      calendar = shop_calendar(same_day: true, order_deadline: ~T[14:00:00])
      now = DateTime.from_naive!(~N[2024-04-02 15:00:00], "Europe/Helsinki")
      assert :past == Availability.customer_cell_state(calendar, ~D[2024-04-02], now)
    end
  end

  describe "admin_cell_state/3" do
    test ":open when weekday rule allows the date" do
      calendar = shop_calendar()
      assert :open == Availability.admin_cell_state(calendar, ~D[2024-04-05], ~D[2024-04-02])
    end

    test ":past when date is before today" do
      calendar = shop_calendar()
      assert :past == Availability.admin_cell_state(calendar, ~D[2024-04-01], ~D[2024-04-02])
    end

    test ":weekday_disabled when weekday is disabled and no explicit enable" do
      calendar =
        shop_calendar(available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday])

      # 2024-04-07 is a Sunday
      assert :weekday_disabled == Availability.admin_cell_state(calendar, ~D[2024-04-07], ~D[2024-04-02])
    end

    test ":date_disabled when date is explicitly disabled" do
      calendar = shop_calendar(disabled_dates: [~D[2024-04-10]])
      assert :date_disabled == Availability.admin_cell_state(calendar, ~D[2024-04-10], ~D[2024-04-02])
    end

    test ":open when date is explicitly enabled on an otherwise-closed weekday" do
      # 2024-04-07 is a Sunday
      calendar =
        shop_calendar(
          available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday],
          enabled_dates: [~D[2024-04-07]]
        )

      assert :open == Availability.admin_cell_state(calendar, ~D[2024-04-07], ~D[2024-04-02])
    end

    test "today is not collapsed to :past — same-day rules don't apply to admin" do
      calendar = shop_calendar(same_day: false, order_deadline: ~T[14:00:00])
      assert :open == Availability.admin_cell_state(calendar, ~D[2024-04-02], ~D[2024-04-02])
    end
  end

  describe "override?/2" do
    test "true when the date is in enabled_dates" do
      calendar = shop_calendar(enabled_dates: [~D[2024-04-07]])
      assert Availability.override?(calendar, ~D[2024-04-07])
    end

    test "true when the date is in disabled_dates" do
      calendar = shop_calendar(disabled_dates: [~D[2024-04-10]])
      assert Availability.override?(calendar, ~D[2024-04-10])
    end

    test "false for a date governed only by the weekday rule" do
      calendar = shop_calendar()
      refute Availability.override?(calendar, ~D[2024-04-10])
    end
  end

  describe "next_open_date/2" do
    test "today when same day is on and the deadline hasn't passed" do
      calendar = shop_calendar(same_day: true, order_deadline: ~T[14:00:00])
      now = DateTime.from_naive!(~N[2023-06-01 13:00:00], "Europe/Helsinki")

      assert ~D[2023-06-01] == Availability.next_open_date(calendar, now)
    end

    test "skips today after the deadline and closed days" do
      calendar = shop_calendar(same_day: true, order_deadline: ~T[14:00:00], disabled_dates: [~D[2023-06-02]])
      now = DateTime.from_naive!(~N[2023-06-01 15:00:00], "Europe/Helsinki")

      assert ~D[2023-06-03] == Availability.next_open_date(calendar, now)
    end

    test "nil when the shop is closed every day" do
      calendar = shop_calendar(available_days: [])
      now = DateTime.from_naive!(~N[2023-06-01 10:00:00], "Europe/Helsinki")

      assert nil == Availability.next_open_date(calendar, now)
    end
  end
end
