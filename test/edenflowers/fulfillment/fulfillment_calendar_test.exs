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
end
