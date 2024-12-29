defmodule Edenflowers.FulfillmentsTest do
  alias Edenflowers.Fulfillments
  use Edenflowers.DataCase
  import Edenflowers.Fixtures

  setup do
    tax_rate = fixture(:tax_rate)
    [tax_rate_id: tax_rate.id]
  end

  describe "calculate_price/1" do
    test "calculates fixed pricing", %{tax_rate_id: tax_rate_id} do
      fulfillment_option = fixture(:fulfillment_option, tax_rate_id: tax_rate_id, type: :fixed, base_price: 0)
      assert Fulfillments.calculate_price(fulfillment_option) == {:ok, Decimal.new("0")}
    end
  end

  describe "calculate_price/2" do
    setup %{tax_rate_id: tax_rate_id} do
      fulfillment_option =
        fixture(:fulfillment_option,
          tax_rate_id: tax_rate_id,
          type: :dynamic,
          base_price: "4.50",
          price_per_km: "1.60",
          free_dist_km: 5,
          max_dist_km: 20
        )

      [fulfillment_option: fulfillment_option]
    end

    test "returns value when distance is within free delivery range", %{fulfillment_option: fulfillment_option} do
      assert Fulfillments.calculate_price(fulfillment_option, 4999) == {:ok, Decimal.new("0")}
      assert Fulfillments.calculate_price(fulfillment_option, 5000) == {:ok, Decimal.new("0")}
      assert Fulfillments.calculate_price(fulfillment_option, 5001) == {:ok, Decimal.new("4.50")}
    end

    test "returns value when distance is within paid delivery range", %{fulfillment_option: fulfillment_option} do
      assert Fulfillments.calculate_price(fulfillment_option, 7250) == {:ok, Decimal.new("8.10")}
    end

    test "returns error when distance is outside of delivery range", %{fulfillment_option: fulfillment_option} do
      assert Fulfillments.calculate_price(fulfillment_option, 20000) == {:error, :out_of_delivery_range}
    end
  end

  describe "fulfill_on_date/3" do
    test "returns :past when date is in the past", %{tax_rate_id: tax_rate_id} do
      fulfillment_option = fixture(:fulfillment_option, tax_rate_id: tax_rate_id)

      now = DateTime.from_naive!(~N[2023-09-15 10:30:00], "Europe/Helsinki")

      assert Fulfillments.fulfill_on_date(fulfillment_option, ~D[2023-09-14], now) == {false, :past}
    end

    test "returns :day_of_week_disabled when day of week is disabled", %{tax_rate_id: tax_rate_id} do
      fulfillment_option = fixture(:fulfillment_option, tax_rate_id: tax_rate_id, sunday: false)

      now = DateTime.from_naive!(~N[2023-09-09 20:15:00], "Europe/Helsinki")

      # 10th Sept 2023 is a Sunday
      assert Fulfillments.fulfill_on_date(fulfillment_option, ~D[2023-09-10], now) == {false, :day_of_week_disabled}
    end

    test "returns :same_day_delivery_disabled when same day fulfillment is not enabled", %{tax_rate_id: tax_rate_id} do
      fulfillment_option =
        fixture(:fulfillment_option, tax_rate_id: tax_rate_id, same_day: false, order_deadline: ~T[14:00:00])

      now = DateTime.from_naive!(~N[2023-09-20 09:45:00], "Europe/Helsinki")

      assert Fulfillments.fulfill_on_date(fulfillment_option, ~D[2023-09-20], now) ==
               {false, :same_day_delivery_disabled}
    end

    test "returns :ok when same day fulfillment is enabled", %{tax_rate_id: tax_rate_id} do
      fulfillment_option =
        fixture(:fulfillment_option, tax_rate_id: tax_rate_id, same_day: true, order_deadline: ~T[14:00:00])

      now = DateTime.from_naive!(~N[2023-06-01 13:59:00], "Europe/Helsinki")

      assert Fulfillments.fulfill_on_date(fulfillment_option, ~D[2023-06-01], now) == {true, :ok}
    end

    test "returns :order_deadline_passed when same day fulfillment is enabled but time is past cutoff", %{
      tax_rate_id: tax_rate_id
    } do
      fulfillment_option =
        fixture(:fulfillment_option, tax_rate_id: tax_rate_id, same_day: true, order_deadline: ~T[14:00:00])

      now = DateTime.from_naive!(~N[2023-06-01 14:01:00], "Europe/Helsinki")

      assert Fulfillments.fulfill_on_date(fulfillment_option, ~D[2023-06-01], now) == {false, :order_deadline_passed}
    end

    test "returns :disabled if date is disabled", %{tax_rate_id: tax_rate_id} do
      fulfillment_option = fixture(:fulfillment_option, tax_rate_id: tax_rate_id, disabled_dates: [~D[2023-02-15]])

      now = DateTime.from_naive!(~N[2023-02-10 12:00:00], "Europe/Helsinki")

      assert Fulfillments.fulfill_on_date(fulfillment_option, ~D[2023-02-15], now) ==
               {false, :date_disabled}
    end

    test "fulfillment date overrides weekday 1/2", %{tax_rate_id: tax_rate_id} do
      # Disable fulfillment on Sundays except on Sunday 7th April 2024
      fulfillment_option =
        fixture(:fulfillment_option, tax_rate_id: tax_rate_id, sunday: false, enabled_dates: [~D[2024-04-07]])

      now = DateTime.from_naive!(~N[2024-04-06 09:20:00], "Europe/Helsinki")
      assert Fulfillments.fulfill_on_date(fulfillment_option, ~D[2024-04-07], now) == {true, :ok}
    end

    test "fulfillment date overrides weekday 2/2", %{tax_rate_id: tax_rate_id} do
      # Enable fulfillment on Wednesdays except on Wednesday 3rd April 2024
      fulfillment_option =
        fixture(:fulfillment_option, tax_rate_id: tax_rate_id, wednesday: true, disabled_dates: [~D[2024-04-03]])

      now = DateTime.from_naive!(~N[2024-04-02 17:50:00], "Europe/Helsinki")

      assert Fulfillments.fulfill_on_date(fulfillment_option, ~D[2024-04-03], now) ==
               {false, :date_disabled}
    end
  end
end
