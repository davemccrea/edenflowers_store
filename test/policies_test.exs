defmodule Edenflowers.PoliciesTest do
  @moduledoc """
  Verifies that create/update/destroy on resources without an authenticated
  admin (or system actor, where applicable) are explicitly forbidden.
  """
  use Edenflowers.DataCase
  import Generator

  alias Edenflowers.Services.Course

  alias Edenflowers.Store.{
    FulfillmentOption,
    Product,
    ProductCategory,
    ProductVariant,
    Promotion,
    TaxRate
  }

  describe "Promotion mutations require admin or system actor" do
    setup do
      {:ok, promotion: generate(promotion())}
    end

    test "create is forbidden for unauthenticated actor" do
      assert {:error, %Ash.Error.Forbidden{}} =
               Promotion
               |> Ash.Changeset.for_create(:create, %{
                 name: "Test",
                 code: "TEST",
                 discount_percentage: "0.10",
                 minimum_cart_total: "0"
               })
               |> Ash.create()
    end

    test "update (increment_usage) is forbidden for unauthenticated actor", %{promotion: promotion} do
      assert {:error, %Ash.Error.Forbidden{}} =
               promotion
               |> Ash.Changeset.for_update(:increment_usage, %{})
               |> Ash.update()
    end

    test "destroy is forbidden for unauthenticated actor", %{promotion: promotion} do
      assert {:error, %Ash.Error.Forbidden{}} = Ash.destroy(promotion)
    end

    test "create is forbidden for non-admin actor" do
      assert {:error, %Ash.Error.Forbidden{}} =
               Promotion
               |> Ash.Changeset.for_create(:create, %{
                 name: "Test",
                 code: "TEST",
                 discount_percentage: "0.10",
                 minimum_cart_total: "0"
               })
               |> Ash.create(actor: %{admin: false})
    end
  end

  describe "Product mutations require admin actor" do
    setup do
      tax_rate = generate(tax_rate())
      product_category = generate(product_category())
      {:ok, product: generate(product()), tax_rate: tax_rate, product_category: product_category}
    end

    test "create is forbidden for unauthenticated actor", %{tax_rate: tax_rate, product_category: pc} do
      assert {:error, %Ash.Error.Forbidden{}} =
               Product
               |> Ash.Changeset.for_create(:create, %{
                 name: "Test product",
                 description: "",
                 image_slug: "x.png",
                 tax_rate_id: tax_rate.id,
                 product_category_id: pc.id
               })
               |> Ash.create()
    end

    test "destroy is forbidden for unauthenticated actor", %{product: product} do
      assert {:error, %Ash.Error.Forbidden{}} = Ash.destroy(product)
    end
  end

  describe "ProductVariant mutations require admin actor" do
    setup do
      product = generate(product())
      variant = generate(product_variant(product_id: product.id))
      {:ok, product: product, variant: variant}
    end

    test "create is forbidden for unauthenticated actor", %{product: product} do
      assert {:error, %Ash.Error.Forbidden{}} =
               ProductVariant
               |> Ash.Changeset.for_create(:create, %{
                 price: "10.00",
                 size: :small,
                 image_slug: "x.png",
                 product_id: product.id
               })
               |> Ash.create()
    end

    test "update is forbidden for unauthenticated actor", %{variant: variant} do
      assert {:error, %Ash.Error.Forbidden{}} =
               variant
               |> Ash.Changeset.for_update(:update, %{price: "20.00"})
               |> Ash.update()
    end

    test "destroy is forbidden for unauthenticated actor", %{variant: variant} do
      assert {:error, %Ash.Error.Forbidden{}} = Ash.destroy(variant)
    end
  end

  describe "ProductCategory mutations require admin actor" do
    setup do
      {:ok, category: generate(product_category())}
    end

    test "create is forbidden for unauthenticated actor" do
      assert {:error, %Ash.Error.Forbidden{}} =
               ProductCategory
               |> Ash.Changeset.for_create(:create, %{name: "Test", slug: "test"})
               |> Ash.create()
    end

    test "update is forbidden for unauthenticated actor", %{category: category} do
      assert {:error, %Ash.Error.Forbidden{}} =
               category
               |> Ash.Changeset.for_update(:update, %{name: "Renamed"})
               |> Ash.update()
    end

    test "destroy is forbidden for unauthenticated actor", %{category: category} do
      assert {:error, %Ash.Error.Forbidden{}} = Ash.destroy(category)
    end
  end

  describe "TaxRate mutations require admin actor" do
    setup do
      {:ok, tax_rate: generate(tax_rate())}
    end

    test "create is forbidden for unauthenticated actor" do
      assert {:error, %Ash.Error.Forbidden{}} =
               TaxRate
               |> Ash.Changeset.for_create(:create, %{name: "VAT", percentage: "0.24"})
               |> Ash.create()
    end

    test "destroy is forbidden for unauthenticated actor", %{tax_rate: tax_rate} do
      assert {:error, %Ash.Error.Forbidden{}} = Ash.destroy(tax_rate)
    end
  end

  describe "FulfillmentOption mutations require admin actor" do
    setup do
      tax_rate = generate(tax_rate())
      option = generate(fulfillment_option(tax_rate_id: tax_rate.id))
      {:ok, option: option, tax_rate: tax_rate}
    end

    test "create is forbidden for unauthenticated actor", %{tax_rate: tax_rate} do
      assert {:error, %Ash.Error.Forbidden{}} =
               FulfillmentOption
               |> Ash.Changeset.for_create(:create, %{
                 name: "Test",
                 fulfillment_method: :pickup,
                 rate_type: :fixed,
                 base_price: "0.00",
                 tax_rate_id: tax_rate.id
               })
               |> Ash.create()
    end

    test "update is forbidden for unauthenticated actor", %{option: option} do
      assert {:error, %Ash.Error.Forbidden{}} =
               option
               |> Ash.Changeset.for_update(:update, %{base_price: "9.99"})
               |> Ash.update()
    end

    test "destroy is forbidden for unauthenticated actor", %{option: option} do
      assert {:error, %Ash.Error.Forbidden{}} = Ash.destroy(option)
    end
  end

  describe "Course mutations require admin actor" do
    setup do
      course =
        Course
        |> Ash.Changeset.for_create(:create, %{
          name: "Course",
          description: "Description",
          location_name: "Studio",
          location_address: "1 Street",
          image_slug: "x.png",
          date: ~D[2030-01-01],
          start_time: ~T[10:00:00],
          end_time: ~T[12:00:00],
          register_before: ~D[2029-12-25],
          total_places: 10,
          price: "50.00"
        })
        |> Ash.create!(authorize?: false)

      {:ok, course: course}
    end

    test "create is forbidden for unauthenticated actor" do
      assert {:error, %Ash.Error.Forbidden{}} =
               Course
               |> Ash.Changeset.for_create(:create, %{
                 name: "Course",
                 description: "Description",
                 location_name: "Studio",
                 location_address: "1 Street",
                 image_slug: "x.png",
                 date: ~D[2030-01-01],
                 start_time: ~T[10:00:00],
                 end_time: ~T[12:00:00],
                 register_before: ~D[2029-12-25],
                 total_places: 10,
                 price: "50.00"
               })
               |> Ash.create()
    end

    test "update is forbidden for unauthenticated actor", %{course: course} do
      assert {:error, %Ash.Error.Forbidden{}} =
               course
               |> Ash.Changeset.for_update(:update, %{total_places: 20})
               |> Ash.update()
    end

    test "destroy is forbidden for unauthenticated actor", %{course: course} do
      assert {:error, %Ash.Error.Forbidden{}} = Ash.destroy(course)
    end
  end
end
