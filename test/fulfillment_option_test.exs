defmodule Edenflowers.Store.FulfillmentOptionTest do
  use Edenflowers.DataCase
  import Generator
  alias Edenflowers.Store.FulfillmentOption

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

  describe "FulfillmentOption minimum_cart_total" do
    test "creates fulfillment option with minimum_cart_total", %{tax_rate: tax_rate} do
      assert {:ok, option} =
               FulfillmentOption
               |> Ash.Changeset.for_create(:create, %{
                 name: "Premium Delivery",
                 fulfillment_method: :delivery,
                 rate_type: :fixed,
                 base_price: "5.00",
                 minimum_cart_total: "50.00",
                 tax_rate_id: tax_rate.id
               })
               |> Ash.create(authorize?: false)

      assert Decimal.equal?(option.minimum_cart_total, "50.00")
    end

    test "defaults minimum_cart_total to 0", %{tax_rate: tax_rate} do
      assert {:ok, option} =
               FulfillmentOption
               |> Ash.Changeset.for_create(:create, %{
                 name: "Standard Delivery",
                 fulfillment_method: :delivery,
                 rate_type: :fixed,
                 base_price: "3.00",
                 tax_rate_id: tax_rate.id
               })
               |> Ash.create(authorize?: false)

      assert Decimal.equal?(option.minimum_cart_total, "0")
    end

    test "allows fulfillment option with zero minimum", %{tax_rate: tax_rate} do
      assert {:ok, option} =
               FulfillmentOption
               |> Ash.Changeset.for_create(:create, %{
                 name: "Free Delivery",
                 fulfillment_method: :delivery,
                 rate_type: :fixed,
                 base_price: "0.00",
                 minimum_cart_total: "0",
                 tax_rate_id: tax_rate.id
               })
               |> Ash.create(authorize?: false)

      assert Decimal.equal?(option.minimum_cart_total, "0")
    end
  end
end
