defmodule Edenflowers.Fulfillment.FulfillmentOptionTest do
  use Edenflowers.DataCase
  import Generator
  alias Edenflowers.Fulfillment.FulfillmentOption

  setup do
    tax_rate = generate(tax_rate())
    {:ok, tax_rate: tax_rate}
  end

  describe "Fulfillment Option Resource" do
    test "creates fulfillment option of type :dynamic", %{tax_rate: tax_rate} do
      assert {:ok, _option} =
               FulfillmentOption
               |> Ash.Changeset.for_create(:create, %{
                 name: "Home delivery",
                 fulfillment_method: :delivery,
                 rate_type: :dynamic,
                 minimum_cart_total: 0,
                 base_price: "3.00",
                 price_per_km: "1.50",
                 free_dist_km: 5,
                 max_dist_km: 20,
                 tax_rate_id: tax_rate.id
               })
               |> Ash.create(authorize?: false)
    end

    test "fails to create fulfillment option of rate_type :dynamic if missing fields" do
      assert {:error, result} =
               FulfillmentOption
               |> Ash.Changeset.for_create(:create, %{name: "Home delivery", rate_type: :dynamic})
               |> Ash.create(authorize?: false)

      assert "price_per_km,free_dist_km,max_dist_km" =
               result
               |> Map.get(:errors)
               |> List.first()
               |> Map.get(:vars)
               |> Keyword.get(:keys)
    end

    test "creates fulfillment option of rate_type :fixed", %{tax_rate: tax_rate} do
      assert {:ok, _} =
               Ash.Changeset.for_create(FulfillmentOption, :create, %{
                 name: "In store pickup",
                 fulfillment_method: :pickup,
                 rate_type: :fixed,
                 base_price: "0.00",
                 tax_rate_id: tax_rate.id
               })
               |> Ash.create(authorize?: false)
    end

    test "fails to create fulfillment option when same_day is true and order_deadline is not present" do
      assert {:error, _} =
               FulfillmentOption
               |> Ash.Changeset.for_create(:create, %{
                 name: "In store pickup",
                 type: :fixed,
                 base_price: "0.00",
                 same_day: true,
                 order_deadline: nil
               })
               |> Ash.create(authorize?: false)
    end

    test "creates fulfillment option when same_day is true and order_deadline is present", %{tax_rate: tax_rate} do
      assert {:ok, _} =
               FulfillmentOption
               |> Ash.Changeset.for_create(:create, %{
                 name: "In store pickup",
                 fulfillment_method: :pickup,
                 rate_type: :fixed,
                 base_price: "0.00",
                 same_day: true,
                 order_deadline: ~T[16:00:00],
                 tax_rate_id: tax_rate.id
               })
               |> Ash.create(authorize?: false)
    end
  end

  describe "calculate_price action" do
    setup %{tax_rate: tax_rate} do
      option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate.id,
            fulfillment_method: :delivery,
            rate_type: :dynamic,
            base_price: "4.50",
            price_per_km: "1.60",
            free_dist_km: 5,
            max_dist_km: 20
          )
        )

      [option: option]
    end

    test "calculates fixed pricing", %{tax_rate: tax_rate} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate.id, rate_type: :fixed, base_price: 0))

      assert {:ok, %{error: nil, fulfillment_fee: Decimal.new("0")}} ==
               FulfillmentOption.calculate_price(option.id, Decimal.new("0"))
    end

    test "returns value when distance is within free delivery range", %{option: option} do
      assert {:ok, %{error: nil, fulfillment_fee: Decimal.new("0")}} ==
               FulfillmentOption.calculate_price(option.id, Decimal.new(4999))

      assert {:ok, %{error: nil, fulfillment_fee: Decimal.new("0")}} ==
               FulfillmentOption.calculate_price(option.id, Decimal.new(5000))

      assert {:ok, %{error: nil, fulfillment_fee: Decimal.new("4.50")}} ==
               FulfillmentOption.calculate_price(option.id, Decimal.new(5001))
    end

    test "returns value when distance is within paid delivery range", %{option: option} do
      assert {:ok, %{error: nil, fulfillment_fee: Decimal.new("8.10")}} ==
               FulfillmentOption.calculate_price(option.id, Decimal.new(7250))
    end

    test "returns :out_of_delivery_range when distance is beyond the max", %{option: option} do
      assert {:ok, %{error: :out_of_delivery_range, fulfillment_fee: nil}} =
               FulfillmentOption.calculate_price(option.id, Decimal.new(20000))
    end
  end

  describe "fulfill_on_date action" do
    test "returns nil when bookable", %{tax_rate: tax_rate} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate.id))
      now = DateTime.from_naive!(~N[2024-04-02 09:00:00], "Europe/Helsinki")

      assert {:ok, nil} =
               FulfillmentOption.fulfill_on_date(option.id, ~D[2024-04-05], %{now: now}, authorize?: false)
    end

    test "returns :past when the date is in the past", %{tax_rate: tax_rate} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate.id))
      now = DateTime.from_naive!(~N[2024-04-02 09:00:00], "Europe/Helsinki")

      assert {:ok, :past} =
               FulfillmentOption.fulfill_on_date(option.id, ~D[2024-04-01], %{now: now}, authorize?: false)
    end

    test "normalises now to Helsinki for the same-day deadline", %{tax_rate: tax_rate} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate.id, same_day: true, order_deadline: ~T[14:00:00]))
      # 14:01 Helsinki is past the 14:00 cutoff even though its UTC wall-clock is earlier.
      now = DateTime.from_naive!(~N[2024-04-02 14:01:00], "Europe/Helsinki")

      assert {:ok, :order_deadline_passed} =
               FulfillmentOption.fulfill_on_date(option.id, ~D[2024-04-02], %{now: now}, authorize?: false)
    end
  end
end
