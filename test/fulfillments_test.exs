defmodule Edenflowers.FulfillmentsTest do
  use Edenflowers.DataCase
  import Generator
  alias Edenflowers.Fulfillments

  setup do
    tax_rate = generate(tax_rate())
    [tax_rate_id: tax_rate.id]
  end

  describe "calculate_price/1" do
    test "calculates fixed pricing", %{tax_rate_id: tax_rate_id} do
      fulfillment_option = generate(fulfillment_option(tax_rate_id: tax_rate_id, rate_type: :fixed, base_price: 0))
      assert {:ok, Decimal.new("0")} == Fulfillments.calculate_price(fulfillment_option)
    end
  end

  describe "calculate_price/2" do
    setup %{tax_rate_id: tax_rate_id} do
      fulfillment_option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            fulfillment_method: :delivery,
            rate_type: :dynamic,
            base_price: "4.50",
            price_per_km: "1.60",
            free_dist_km: 5,
            max_dist_km: 20
          )
        )

      [fulfillment_option: fulfillment_option]
    end

    test "returns value when distance is within free delivery range", %{fulfillment_option: fulfillment_option} do
      assert {:ok, Decimal.new("0")} == Fulfillments.calculate_price(fulfillment_option, 4999)
      assert {:ok, Decimal.new("0")} == Fulfillments.calculate_price(fulfillment_option, 5000)
      assert {:ok, Decimal.new("4.50")} == Fulfillments.calculate_price(fulfillment_option, 5001)
    end

    test "returns value when distance is within paid delivery range", %{fulfillment_option: fulfillment_option} do
      assert {:ok, Decimal.new("8.10")} == Fulfillments.calculate_price(fulfillment_option, 7250)
    end

    test "returns error when distance is outside of delivery range", %{fulfillment_option: fulfillment_option} do
      assert {:error, :out_of_delivery_range} = Fulfillments.calculate_price(fulfillment_option, 20000)
    end
  end

  describe "fulfill_on_date/3" do
    test "returns :past when date is in the past", %{tax_rate_id: tax_rate_id} do
      fulfillment_option = generate(fulfillment_option(tax_rate_id: tax_rate_id))

      now = DateTime.from_naive!(~N[2023-09-15 10:30:00], "Europe/Helsinki")

      assert {false, :past} = Fulfillments.fulfill_on_date(fulfillment_option, ~D[2023-09-14], now)
    end

    test "returns :weekday_disabled when day of week is disabled", %{tax_rate_id: tax_rate_id} do
      fulfillment_option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
          )
        )

      now = DateTime.from_naive!(~N[2023-09-09 20:15:00], "Europe/Helsinki")

      # 10th Sept 2023 is a Sunday
      assert {false, :weekday_disabled} = Fulfillments.fulfill_on_date(fulfillment_option, ~D[2023-09-10], now)
    end

    test "returns :same_day_delivery_disabled when same day fulfillment is not enabled", %{tax_rate_id: tax_rate_id} do
      fulfillment_option =
        generate(fulfillment_option(tax_rate_id: tax_rate_id, same_day: false, order_deadline: ~T[14:00:00]))

      now = DateTime.from_naive!(~N[2023-09-20 09:45:00], "Europe/Helsinki")

      assert {false, :same_day_delivery_disabled} =
               Fulfillments.fulfill_on_date(fulfillment_option, ~D[2023-09-20], now)
    end

    test "returns :ok when same day fulfillment is enabled", %{tax_rate_id: tax_rate_id} do
      fulfillment_option =
        generate(fulfillment_option(tax_rate_id: tax_rate_id, same_day: true, order_deadline: ~T[14:00:00]))

      now = DateTime.from_naive!(~N[2023-06-01 13:59:00], "Europe/Helsinki")

      assert {true, :ok} = Fulfillments.fulfill_on_date(fulfillment_option, ~D[2023-06-01], now)
    end

    test "returns :order_deadline_passed when same day fulfillment is enabled but time is past cutoff", %{
      tax_rate_id: tax_rate_id
    } do
      fulfillment_option =
        generate(fulfillment_option(tax_rate_id: tax_rate_id, same_day: true, order_deadline: ~T[14:00:00]))

      now = DateTime.from_naive!(~N[2023-06-01 14:01:00], "Europe/Helsinki")

      assert {false, :order_deadline_passed} =
               Fulfillments.fulfill_on_date(fulfillment_option, ~D[2023-06-01], now)
    end

    test "returns :disabled if date is disabled", %{tax_rate_id: tax_rate_id} do
      fulfillment_option = generate(fulfillment_option(tax_rate_id: tax_rate_id, disabled_dates: [~D[2023-02-15]]))

      now = DateTime.from_naive!(~N[2023-02-10 12:00:00], "Europe/Helsinki")

      assert {false, :date_disabled} = Fulfillments.fulfill_on_date(fulfillment_option, ~D[2023-02-15], now)
    end

    test "fulfillment date overrides weekday 1/2", %{tax_rate_id: tax_rate_id} do
      # Disable fulfillment on Sundays except on Sunday 7th April 2024
      fulfillment_option =
        generate(fulfillment_option(tax_rate_id: tax_rate_id, sunday: false, enabled_dates: [~D[2024-04-07]]))

      now = DateTime.from_naive!(~N[2024-04-06 09:20:00], "Europe/Helsinki")
      assert {true, :ok} = Fulfillments.fulfill_on_date(fulfillment_option, ~D[2024-04-07], now)
    end

    test "fulfillment date overrides weekday 2/2", %{tax_rate_id: tax_rate_id} do
      # Enable fulfillment on Wednesdays except on Wednesday 3rd April 2024
      fulfillment_option =
        generate(fulfillment_option(tax_rate_id: tax_rate_id, wednesday: true, disabled_dates: [~D[2024-04-03]]))

      now = DateTime.from_naive!(~N[2024-04-02 17:50:00], "Europe/Helsinki")

      assert {false, :date_disabled} =
               Fulfillments.fulfill_on_date(fulfillment_option, ~D[2024-04-03], now)
    end
  end

  describe "customer_cell_state/3" do
    test ":open when fulfillable", %{tax_rate_id: tax_rate_id} do
      fulfillment_option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      now = DateTime.from_naive!(~N[2024-04-02 09:00:00], "Europe/Helsinki")
      assert :open == Fulfillments.customer_cell_state(fulfillment_option, ~D[2024-04-05], now)
    end

    test ":past when date is before today", %{tax_rate_id: tax_rate_id} do
      fulfillment_option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      now = DateTime.from_naive!(~N[2024-04-02 09:00:00], "Europe/Helsinki")
      assert :past == Fulfillments.customer_cell_state(fulfillment_option, ~D[2024-04-01], now)
    end

    test ":closed when weekday is disabled and no explicit enable", %{tax_rate_id: tax_rate_id} do
      fulfillment_option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
          )
        )

      now = DateTime.from_naive!(~N[2024-04-02 09:00:00], "Europe/Helsinki")
      # 2024-04-07 is a Sunday
      assert :closed == Fulfillments.customer_cell_state(fulfillment_option, ~D[2024-04-07], now)
    end

    test ":closed when date is explicitly disabled", %{tax_rate_id: tax_rate_id} do
      fulfillment_option =
        generate(fulfillment_option(tax_rate_id: tax_rate_id, disabled_dates: [~D[2024-04-10]]))

      now = DateTime.from_naive!(~N[2024-04-02 09:00:00], "Europe/Helsinki")
      assert :closed == Fulfillments.customer_cell_state(fulfillment_option, ~D[2024-04-10], now)
    end

    test ":past when same-day disabled and date is today", %{tax_rate_id: tax_rate_id} do
      fulfillment_option =
        generate(fulfillment_option(tax_rate_id: tax_rate_id, same_day: false, order_deadline: ~T[14:00:00]))

      now = DateTime.from_naive!(~N[2024-04-02 09:00:00], "Europe/Helsinki")
      assert :past == Fulfillments.customer_cell_state(fulfillment_option, ~D[2024-04-02], now)
    end

    test ":past when order deadline has passed", %{tax_rate_id: tax_rate_id} do
      fulfillment_option =
        generate(fulfillment_option(tax_rate_id: tax_rate_id, same_day: true, order_deadline: ~T[14:00:00]))

      now = DateTime.from_naive!(~N[2024-04-02 15:00:00], "Europe/Helsinki")
      assert :past == Fulfillments.customer_cell_state(fulfillment_option, ~D[2024-04-02], now)
    end
  end

  describe "admin_cell_state/3" do
    test ":open when weekday rule allows the date", %{tax_rate_id: tax_rate_id} do
      fulfillment_option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      assert :open == Fulfillments.admin_cell_state(fulfillment_option, ~D[2024-04-05], ~D[2024-04-02])
    end

    test ":past when date is before today", %{tax_rate_id: tax_rate_id} do
      fulfillment_option = generate(fulfillment_option(tax_rate_id: tax_rate_id))
      assert :past == Fulfillments.admin_cell_state(fulfillment_option, ~D[2024-04-01], ~D[2024-04-02])
    end

    test ":weekday_disabled when weekday is disabled and no explicit enable", %{tax_rate_id: tax_rate_id} do
      fulfillment_option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
          )
        )

      # 2024-04-07 is a Sunday
      assert :weekday_disabled == Fulfillments.admin_cell_state(fulfillment_option, ~D[2024-04-07], ~D[2024-04-02])
    end

    test ":date_disabled when date is explicitly disabled", %{tax_rate_id: tax_rate_id} do
      fulfillment_option =
        generate(fulfillment_option(tax_rate_id: tax_rate_id, disabled_dates: [~D[2024-04-10]]))

      assert :date_disabled == Fulfillments.admin_cell_state(fulfillment_option, ~D[2024-04-10], ~D[2024-04-02])
    end

    test ":open when date is explicitly enabled on an otherwise-closed weekday", %{tax_rate_id: tax_rate_id} do
      # 2024-04-07 is a Sunday
      fulfillment_option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate_id,
            available_days: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday],
            enabled_dates: [~D[2024-04-07]]
          )
        )

      assert :open == Fulfillments.admin_cell_state(fulfillment_option, ~D[2024-04-07], ~D[2024-04-02])
    end

    test "today is not collapsed to :past — same-day rules don't apply to admin", %{tax_rate_id: tax_rate_id} do
      fulfillment_option =
        generate(fulfillment_option(tax_rate_id: tax_rate_id, same_day: false, order_deadline: ~T[14:00:00]))

      assert :open == Fulfillments.admin_cell_state(fulfillment_option, ~D[2024-04-02], ~D[2024-04-02])
    end
  end
end
