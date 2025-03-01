defmodule Edenflowers.Store.FulfillmentOptionTest do
  use Edenflowers.DataCase
  import Edenflowers.Fixtures
  alias Edenflowers.Store.FulfillmentOption

  describe "Fulfillment Option Resource" do
    test "creates fulfillment option of type :dynamic" do
      tax_rate = fixture(:tax_rate)

      assert {:ok, option} =
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
               |> Ash.create()
    end

    test "fails to create fulfillment option of rate_type :dynamic if missing fields" do
      assert {:error, result} =
               FulfillmentOption
               |> Ash.Changeset.for_create(:create, %{name: "Home delivery", rate_type: :dynamic})
               |> Ash.create()

      assert "price_per_km,free_dist_km,max_dist_km" =
               result
               |> Map.get(:errors)
               |> List.first()
               |> Map.get(:vars)
               |> Keyword.get(:keys)
    end

    test "creates fulfillment option of rate_type :fixed" do
      tax_rate = fixture(:tax_rate)

      assert {:ok, _} =
               Ash.Changeset.for_create(FulfillmentOption, :create, %{
                 name: "In store pickup",
                 fulfillment_method: :pickup,
                 rate_type: :fixed,
                 base_price: "0.00",
                 tax_rate_id: tax_rate.id
               })
               |> Ash.create()
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
               |> Ash.create()
    end

    test "creates fulfillment option when same_day is true and order_deadline is present" do
      tax_rate = fixture(:tax_rate)

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
               |> Ash.create()
    end
  end
end
