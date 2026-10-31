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

    test "can't change anything outside pricing", %{option: option, admin: admin} do
      assert {:error, _} = Fulfillment.update_pricing(option, %{rate_type: :fixed}, actor: admin)
      assert {:error, _} = Fulfillment.update_pricing(option, %{fulfillment_method: :pickup}, actor: admin)
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

    test "a fixed price is the same for every cart", %{tax_rate: tax_rate} do
      option = generate(fulfillment_option(tax_rate_id: tax_rate.id, rate_type: :fixed, base_price: "3.00"))

      assert %{error: nil, fulfillment_fee: Decimal.new("3.00"), free_delivery_fee: Decimal.new("3.00")} ==
               Fulfillment.Fee.calculate(option, 0)
    end

    test "charges the base price plus every km from the shop", %{option: option} do
      assert {"4.50", _} = fees(option, 0)
      # 4.50 + 1.60 × 7.25
      assert {"16.10", _} = fees(option, 7250)
    end

    test "a free-delivery cart pays nothing for the first 5 km", %{option: option} do
      assert fees(option, 0) == {"4.50", "0"}

      assert fees(option, 4000) == {"10.90", "0"}

      assert fees(option, 5000) == {"12.50", "0"}
    end

    test "past 5 km a free-delivery cart pays the base price and only the km beyond 5", %{option: option} do
      # 4.50 + 1.60 × 0.001 rounds to the base price: it jumps by the base price at the boundary.
      assert fees(option, 5001) == {"12.50", "4.50"}

      # 4.50 + 1.60 × 1
      assert fees(option, 6000) == {"14.10", "6.10"}

      # 4.50 + 1.60 × 2.25
      assert fees(option, 7250) == {"16.10", "8.10"}

      # 4.50 + 1.60 × 14.999 = 28.4984
      assert fees(option, 19_999) == {"36.50", "28.50"}
    end

    test "with no free distance a free-delivery cart pays the full fee", %{option: option} do
      option = %{option | free_dist_km: 0}

      assert fees(option, 0) == {"4.50", "4.50"}

      assert fees(option, 6000) == {"14.10", "14.10"}
    end

    test "returns :out_of_delivery_range when distance is beyond the max", %{option: option} do
      assert %{error: :out_of_delivery_range, fulfillment_fee: nil, free_delivery_fee: nil} =
               Fulfillment.Fee.calculate(option, 20_000)
    end
  end

  # Both fees as strings, so "4.50" and "4.5" don't compare equal.
  defp fees(option, distance) do
    %{error: nil, fulfillment_fee: fee, free_delivery_fee: free_delivery_fee} =
      Fulfillment.Fee.calculate(option, distance)

    {Decimal.to_string(fee), Decimal.to_string(free_delivery_fee)}
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

      assert Decimal.eq?(fee, Decimal.new("16.10"))
    end
  end
end
