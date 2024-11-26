defmodule Edenflowers.Store.PromotionTest do
  alias Edenflowers.Store.Promotion
  use Edenflowers.DataCase

  describe "Promotion Resource" do
    test "creates a promotion" do
      assert {:ok, _promotion} =
               Promotion
               |> Ash.Changeset.for_create(:create, %{
                 name: "A promotion",
                 code: "CHRISTMAS20",
                 discount_percentage: "0.20",
                 minimum_cart_total: "30.00",
                 start_date: ~D[2024-12-19],
                 expiration_date: ~D[2024-12-31]
               })
               |> Ash.create()
    end

    test "gets promotion using a code with mixed case" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_percentage: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19]
      })
      |> Ash.create!()

      assert {:ok, %Promotion{}} =
               Promotion
               |> Ash.Query.for_read(:by_code, %{code: "Christmas20", today: ~D[2024-12-20]})
               |> Ash.read_one()
    end

    test "gets promotion using a code with leading and trailing whitespace" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_percentage: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19]
      })
      |> Ash.create!()

      assert {:ok, %Promotion{}} =
               Promotion
               |> Ash.Query.for_read(:by_code, %{code: " CHRISTMAS20 ", today: ~D[2024-12-20]})
               |> Ash.read_one()
    end

    test "fails to get promotion if code doesn't match" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_percentage: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19]
      })
      |> Ash.create!()

      assert {:ok, nil} =
               Promotion
               |> Ash.Query.for_read(:by_code, %{code: "AUTUMN20", today: ~D[2024-12-20]})
               |> Ash.read_one()
    end

    test "fails to get promotion if current date is before start date" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_percentage: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19]
      })
      |> Ash.create!()

      assert {:ok, nil} =
               Promotion
               |> Ash.Query.for_read(:by_code, %{code: "CHRISTMAS20", today: ~D[2024-12-18]})
               |> Ash.read_one()
    end

    test "gets promotion if current date is same as start date" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_percentage: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19]
      })
      |> Ash.create!()

      assert {:ok, %Promotion{}} =
               Promotion
               |> Ash.Query.for_read(:by_code, %{code: "CHRISTMAS20", today: ~D[2024-12-19]})
               |> Ash.read_one()
    end

    test "gets promotion if current date is after start date and before expiration date" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_percentage: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19],
        expiration_date: ~D[2024-12-22]
      })
      |> Ash.create!()

      assert {:ok, %Promotion{}} =
               Promotion
               |> Ash.Query.for_read(:by_code, %{code: "CHRISTMAS20", today: ~D[2024-12-21]})
               |> Ash.read_one()
    end

    test "gets promotion if current date is after start date and on expiration date" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_percentage: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19],
        expiration_date: ~D[2024-12-22]
      })
      |> Ash.create!()

      assert {:ok, %Promotion{}} =
               Promotion
               |> Ash.Query.for_read(:by_code, %{code: "CHRISTMAS20", today: ~D[2024-12-22]})
               |> Ash.read_one()
    end

    test "fails to get promotion if current date is after expiration date" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_percentage: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19],
        expiration_date: ~D[2024-12-22]
      })
      |> Ash.create!()

      assert {:ok, nil} =
               Promotion
               |> Ash.Query.for_read(:by_code, %{code: "CHRISTMAS20", today: ~D[2024-12-23]})
               |> Ash.read_one()
    end

    test "gets promotion using code_interface" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_percentage: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19]
      })
      |> Ash.create!()

      assert {:ok, %Promotion{}} = Promotion.get_by_code("CHRISTMAS20")
    end
  end
end
