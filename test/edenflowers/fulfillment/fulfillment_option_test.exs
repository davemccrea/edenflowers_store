defmodule Edenflowers.Fulfillment.FulfillmentOptionTest do
  use Edenflowers.DataCase, async: true
  import Generator
  import Mox
  alias Edenflowers.Fulfillment
  alias Edenflowers.Fulfillment.FulfillmentOption

  setup :verify_on_exit!

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

  describe "pricing validations" do
    setup %{tax_rate: tax_rate} do
      valid = %{
        name: "Home delivery",
        fulfillment_method: :delivery,
        rate_type: :dynamic,
        base_price: "3.00",
        price_per_km: "1.50",
        free_dist_km: 5,
        max_dist_km: 20,
        tax_rate_id: tax_rate.id
      }

      create = fn overrides ->
        FulfillmentOption
        |> Ash.Changeset.for_create(:create, Map.merge(valid, Map.new(overrides)))
        |> Ash.create(authorize?: false)
      end

      [create: create]
    end

    test "rejects a negative base_price", %{create: create} do
      assert {:error, _} = create.(base_price: "-1.00")
    end

    test "rejects a negative price_per_km", %{create: create} do
      assert {:error, _} = create.(price_per_km: "-0.50")
    end

    test "rejects fractional-cent prices", %{create: create} do
      for field <- [:base_price, :price_per_km] do
        assert {:error, _} = create.([{field, "1.001"}])
      end
    end

    test "rejects a negative free_dist_km", %{create: create} do
      assert {:error, _} = create.(free_dist_km: -1)
    end

    test "rejects a max_dist_km of zero", %{create: create} do
      assert {:error, _} = create.(max_dist_km: 0)
    end

    test "rejects free_dist_km greater than max_dist_km", %{create: create} do
      assert {:error, _} = create.(free_dist_km: 20, max_dist_km: 5)
    end

    test "allows free_dist_km equal to max_dist_km", %{create: create} do
      assert {:ok, _} = create.(free_dist_km: 10, max_dist_km: 10)
    end

    test "ignores dynamic pricing fields for a :fixed option", %{create: create} do
      assert {:ok, _} =
               create.(rate_type: :fixed, price_per_km: nil, free_dist_km: nil, max_dist_km: nil)
    end

    test "enforces free_dist_km <= max_dist_km on update too", %{create: create} do
      {:ok, option} = create.(%{})

      assert {:error, _} =
               option
               |> Ash.Changeset.for_update(:update, %{free_dist_km: 30})
               |> Ash.update(authorize?: false)
    end
  end

  describe "update_pricing action" do
    setup %{tax_rate: tax_rate} do
      option =
        generate(fulfillment_option(tax_rate_id: tax_rate.id, fulfillment_method: :delivery, rate_type: :dynamic))

      [option: option, admin: generate(admin_user())]
    end

    test "updates prices, distances and the same-day cutoff", %{option: option, admin: admin} do
      assert {:ok, updated} =
               Fulfillment.update_pricing(
                 option,
                 %{
                   base_price: "5.00",
                   price_per_km: "2.00",
                   free_dist_km: 8,
                   max_dist_km: 25,
                   same_day: false,
                   order_deadline: ~T[12:00:00]
                 },
                 actor: admin
               )

      assert Decimal.equal?(updated.base_price, "5.00")
      assert Decimal.equal?(updated.price_per_km, "2.00")
      assert {updated.free_dist_km, updated.max_dist_km} == {8, 25}
      assert {updated.same_day, updated.order_deadline} == {false, ~T[12:00:00]}
    end

    test "can't change anything outside pricing", %{option: option, admin: admin} do
      assert {:error, _} = Fulfillment.update_pricing(option, %{rate_type: :fixed}, actor: admin)
      assert {:error, _} = Fulfillment.update_pricing(option, %{disabled_dates: [Date.utc_today()]}, actor: admin)
    end

    test "rejects free_dist_km greater than max_dist_km", %{option: option, admin: admin} do
      assert {:error, _} = Fulfillment.update_pricing(option, %{free_dist_km: 30, max_dist_km: 20}, actor: admin)
    end

    test "is forbidden to non-admins", %{option: option} do
      customer = generate(admin_user(admin: false))

      assert {:error, %Ash.Error.Forbidden{}} =
               Fulfillment.update_pricing(option, %{base_price: "0.00"}, actor: customer)
    end
  end

  describe "Fee.calculate/2" do
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

      assert %{error: nil, fulfillment_fee: Decimal.new("0"), in_free_delivery_zone: false} ==
               Fulfillment.Fee.calculate(option, 0)
    end

    test "charges the base price within the free delivery zone", %{option: option} do
      assert %{error: nil, fulfillment_fee: Decimal.new("4.50"), in_free_delivery_zone: true} ==
               Fulfillment.Fee.calculate(option, 0)

      assert %{error: nil, fulfillment_fee: Decimal.new("4.50"), in_free_delivery_zone: true} ==
               Fulfillment.Fee.calculate(option, 5000)

      assert %{error: nil, fulfillment_fee: Decimal.new("4.50"), in_free_delivery_zone: false} ==
               Fulfillment.Fee.calculate(option, 5001)
    end

    test "returns value when distance is within paid delivery range", %{option: option} do
      assert %{error: nil, fulfillment_fee: Decimal.new("8.10"), in_free_delivery_zone: false} ==
               Fulfillment.Fee.calculate(option, 7250)
    end

    test "returns :out_of_delivery_range when distance is beyond the max", %{option: option} do
      assert %{error: :out_of_delivery_range, fulfillment_fee: nil} = Fulfillment.Fee.calculate(option, 20000)
    end
  end

  describe "calculate_delivery action" do
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

    test "computes the fee from the integer distance route_distance returns", %{option: option} do
      stub(Edenflowers.External.HereAPI.Mock, :geocode, fn _query ->
        {:ok, {"Stadsgatan 3, 65300 Vasa", "63.0951,21.6165", "here-id-123"}}
      end)

      stub(Edenflowers.External.HereAPI.Mock, :route_distance, fn _position -> {:ok, 7250} end)

      assert {:ok, %{error: nil, fulfillment_fee: fee, distance: 7250}} =
               Fulfillment.calculate_delivery("Stadsgatan 3", option.id)

      assert Decimal.eq?(fee, Decimal.new("8.10"))
    end
  end

  describe "fulfill_on_date action" do
    test "returns nil when bookable", %{tax_rate: tax_rate} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate.id))
      now = DateTime.from_naive!(~N[2024-04-02 09:00:00], "Europe/Helsinki")

      assert {:ok, nil} =
               Fulfillment.fulfill_on_date(option.id, ~D[2024-04-05], %{now: now}, authorize?: false)
    end

    test "returns :past when the date is in the past", %{tax_rate: tax_rate} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate.id))
      now = DateTime.from_naive!(~N[2024-04-02 09:00:00], "Europe/Helsinki")

      assert {:ok, :past} =
               Fulfillment.fulfill_on_date(option.id, ~D[2024-04-01], %{now: now}, authorize?: false)
    end

    test "normalises now to Helsinki for the same-day deadline", %{tax_rate: tax_rate} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate.id, same_day: true, order_deadline: ~T[14:00:00]))
      # 14:01 Helsinki is past the 14:00 cutoff even though its UTC wall-clock is earlier.
      now = DateTime.from_naive!(~N[2024-04-02 14:01:00], "Europe/Helsinki")

      assert {:ok, :order_deadline_passed} =
               Fulfillment.fulfill_on_date(option.id, ~D[2024-04-02], %{now: now}, authorize?: false)
    end
  end
end
