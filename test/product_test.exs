defmodule Edenflowers.Store.ProductTest do
  use Edenflowers.DataCase
  import Edenflowers.Fixtures

  alias Edenflowers.Store.Product

  describe "Product Resource" do
    test "fails to create product without tax_rate" do
      assert {:error, _} =
               Product
               |> Ash.Changeset.for_create(:create, %{
                 name: "Product 1",
                 description: "Product 1 description"
               })
               |> Ash.create()
    end

    test "creates product when tax_rate is assigned" do
      tax_rate = fixture(:tax_rate)

      assert {:ok, _} =
               Product
               |> Ash.Changeset.for_create(:create, %{
                 tax_rate_id: tax_rate.id,
                 name: "Product 1",
                 description: "Product 1 description"
               })
               |> Ash.create()
    end

    test "fails to create product if product name is not unique" do
      name = "Product 1"
      tax_rate = fixture(:tax_rate)
      _product = fixture(:product, tax_rate_id: tax_rate.id, name: name)

      assert {:error, error} =
               Product
               |> Ash.Changeset.for_create(:create, %{
                 tax_rate_id: tax_rate.id,
                 name: name,
                 description: "Product 1 description"
               })
               |> Ash.create()

      assert %Ash.Error.Invalid{
               errors: [
                 %Ash.Error.Changes.InvalidAttribute{
                   field: :name,
                   message: "has already been taken"
                 }
               ]
             } = error
    end

    test "assigns fulfillment option to product" do
      tax_rate = fixture(:tax_rate)
      fulfillment_option = fixture(:fulfillment_option, tax_rate_id: tax_rate.id)

      fulfillment_option_id = fulfillment_option.id

      assert {:ok, %{fulfillment_options: [%{id: ^fulfillment_option_id}]} = _} =
               Product
               |> Ash.Changeset.for_create(:create, %{
                 tax_rate_id: tax_rate.id,
                 name: "Product 1",
                 description: "Product 1 description",
                 fulfillment_option_ids: [fulfillment_option_id]
               })
               |> Ash.create()
    end

    test "fails to assign fulfillment option to product if fulfillment option does not exist" do
      tax_rate = fixture(:tax_rate)

      # Non existing resource
      id = Ecto.UUID.generate()

      assert {:error, _} =
               Product
               |> Ash.Changeset.for_create(:create, %{
                 tax_rate_id: tax_rate.id,
                 name: "Product 1",
                 description: "Product 1 description",
                 fulfillment_option_ids: [id]
               })
               |> Ash.create()
    end
  end
end
