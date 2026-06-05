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
    LineItem,
    Order,
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
      assert {:error, error} =
               Promotion
               |> Ash.Changeset.for_create(:create, %{
                 name: "Test",
                 code: "TEST",
                 discount_rate: "0.10",
                 minimum_cart_total: "0"
               })
               |> Ash.create(actor: nil)

      assert %Ash.Error.Forbidden{} = error
    end

    test "update (increment_usage) is forbidden for unauthenticated actor", %{promotion: promotion} do
      assert {:error, error} =
               promotion
               |> Ash.Changeset.for_update(:increment_usage, %{}, actor: nil)
               |> Ash.update(actor: nil)

      assert %Ash.Error.Forbidden{} = error
    end

    test "destroy is forbidden for unauthenticated actor", %{promotion: promotion} do
      assert {:error, error} = Ash.destroy(promotion, actor: nil)
      assert %Ash.Error.Forbidden{} = error
    end

    test "system actor can increment usage", %{promotion: promotion} do
      assert {:ok, _} = Promotion.increment_usage(promotion, actor: %{system: true})
    end

    test "system actor cannot create a promotion" do
      assert {:error, %Ash.Error.Forbidden{}} =
               Promotion
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   name: "Stealth",
                   code: "STEALTH",
                   discount_rate: "0.50",
                   minimum_cart_total: "0"
                 },
                 actor: %{system: true}
               )
               |> Ash.create(actor: %{system: true})
    end

    test "system actor cannot destroy a promotion", %{promotion: promotion} do
      assert {:error, %Ash.Error.Forbidden{}} = Ash.destroy(promotion, actor: %{system: true})
    end
  end

  describe "Product mutations require admin actor" do
    setup do
      tax_rate = generate(tax_rate())
      product_category = generate(product_category())
      {:ok, product: generate(product()), tax_rate: tax_rate, product_category: product_category}
    end

    test "create is forbidden for unauthenticated actor", %{tax_rate: tax_rate, product_category: pc} do
      assert {:error, error} =
               Product
               |> Ash.Changeset.for_create(:create, %{
                 name: "Test product",
                 description: "Test description",
                 image_slug: "x.png",
                 tax_rate_id: tax_rate.id,
                 product_category_id: pc.id
               })
               |> Ash.create(actor: nil)

      assert %Ash.Error.Forbidden{} = error
    end

    test "destroy is forbidden for unauthenticated actor", %{product: product} do
      assert {:error, error} = Ash.destroy(product, actor: nil)
      assert %Ash.Error.Forbidden{} = error
    end
  end

  describe "ProductVariant mutations require admin actor" do
    setup do
      product = generate(product())
      variant = generate(product_variant(product_id: product.id))
      {:ok, product: product, variant: variant}
    end

    test "create is forbidden for unauthenticated actor", %{product: product} do
      assert {:error, error} =
               ProductVariant
               |> Ash.Changeset.for_create(:create, %{
                 price: "10.00",
                 size: :small,
                 image_slug: "x.png",
                 product_id: product.id
               })
               |> Ash.create(actor: nil)

      assert %Ash.Error.Forbidden{} = error
    end

    test "update is forbidden for unauthenticated actor", %{variant: variant} do
      assert {:error, error} =
               variant
               |> Ash.Changeset.for_update(:update, %{price: "20.00"})
               |> Ash.update(actor: nil)

      assert %Ash.Error.Forbidden{} = error
    end

    test "destroy is forbidden for unauthenticated actor", %{variant: variant} do
      assert {:error, error} = Ash.destroy(variant, actor: nil)
      assert %Ash.Error.Forbidden{} = error
    end
  end

  describe "ProductCategory mutations require admin actor" do
    setup do
      {:ok, category: generate(product_category())}
    end

    test "create is forbidden for unauthenticated actor" do
      assert {:error, error} =
               ProductCategory
               |> Ash.Changeset.for_create(:create, %{name: "Test", slug: "test"})
               |> Ash.create(actor: nil)

      assert %Ash.Error.Forbidden{} = error
    end

    test "update is forbidden for unauthenticated actor", %{category: category} do
      assert {:error, error} =
               category
               |> Ash.Changeset.for_update(:update, %{name: "Renamed"})
               |> Ash.update(actor: nil)

      assert %Ash.Error.Forbidden{} = error
    end

    test "destroy is forbidden for unauthenticated actor", %{category: category} do
      assert {:error, error} = Ash.destroy(category, actor: nil)
      assert %Ash.Error.Forbidden{} = error
    end
  end

  describe "TaxRate mutations require admin actor" do
    setup do
      {:ok, tax_rate: generate(tax_rate())}
    end

    test "create is forbidden for unauthenticated actor" do
      assert {:error, error} =
               TaxRate
               |> Ash.Changeset.for_create(:create, %{name: "VAT", percentage: "0.24"})
               |> Ash.create(actor: nil)

      assert %Ash.Error.Forbidden{} = error
    end

    test "destroy is forbidden for unauthenticated actor", %{tax_rate: tax_rate} do
      assert {:error, error} = Ash.destroy(tax_rate, actor: nil)
      assert %Ash.Error.Forbidden{} = error
    end
  end

  describe "FulfillmentOption mutations require admin actor" do
    setup do
      tax_rate = generate(tax_rate())
      option = generate(fulfillment_option(tax_rate_id: tax_rate.id))
      {:ok, option: option, tax_rate: tax_rate}
    end

    test "create is forbidden for unauthenticated actor", %{tax_rate: tax_rate} do
      assert {:error, error} =
               FulfillmentOption
               |> Ash.Changeset.for_create(:create, %{
                 name: "Test",
                 fulfillment_method: :pickup,
                 rate_type: :fixed,
                 base_price: "0.00",
                 tax_rate_id: tax_rate.id
               })
               |> Ash.create(actor: nil)

      assert %Ash.Error.Forbidden{} = error
    end

    test "update is forbidden for unauthenticated actor", %{option: option} do
      assert {:error, error} =
               option
               |> Ash.Changeset.for_update(:update, %{base_price: "9.99"})
               |> Ash.update(actor: nil)

      assert %Ash.Error.Forbidden{} = error
    end

    test "destroy is forbidden for unauthenticated actor", %{option: option} do
      assert {:error, error} = Ash.destroy(option, actor: nil)
      assert %Ash.Error.Forbidden{} = error
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
      assert {:error, error} =
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
               |> Ash.create(actor: nil)

      assert %Ash.Error.Forbidden{} = error
    end

    test "destroy is forbidden for unauthenticated actor", %{course: course} do
      assert {:error, error} = Ash.destroy(course, actor: nil)
      assert %Ash.Error.Forbidden{} = error
    end
  end

  describe "Order is immutable after :placed" do
    setup do
      order =
        generate(
          order(
            state: :placed,
            payment_status: :paid,
            payment_intent_id: "pi_test",
            ordered_at: DateTime.utc_now()
          )
        )

      {:ok, order: order}
    end

    test "guest cannot update locale", %{order: order} do
      assert {:error, %Ash.Error.Forbidden{}} = Order.update_locale(order, "en-GB", actor: nil)
    end

    test "admin cannot update locale", %{order: order} do
      assert {:error, %Ash.Error.Forbidden{}} =
               Order.update_locale(order, "en-GB", actor: %{admin: true})
    end

    test "system actor cannot update locale", %{order: order} do
      assert {:error, %Ash.Error.Forbidden{}} =
               Order.update_locale(order, "en-GB", actor: %{system: true})
    end

    test "admin cannot attach payment intent", %{order: order} do
      assert {:error, %Ash.Error.Forbidden{}} =
               Order.add_payment_intent_id(order, "pi_admin_override", actor: %{admin: true})
    end

    test "admin cannot mark payment failed on placed order", %{order: order} do
      # The action's own validation also rejects a :paid order; either error
      # class is acceptable since both layers correctly block the mutation.
      assert {:error, error} =
               Order.mark_payment_failed(order, actor: %{admin: true})

      assert match?(%Ash.Error.Forbidden{}, error) or match?(%Ash.Error.Invalid{}, error)
    end

    test "admin can mark a placed order fulfilled", %{order: order} do
      assert {:ok, order} = Order.mark_fulfilled(order, actor: %{admin: true})
      assert order.fulfillment_status == :fulfilled
    end

    test "non-admin cannot mark a placed order fulfilled", %{order: order} do
      assert {:error, %Ash.Error.Forbidden{}} =
               Order.mark_fulfilled(order, actor: %{id: Ash.UUID.generate(), admin: false})
    end

    test "admin can still read a placed order", %{order: order} do
      assert {:ok, _} = Order.get_by_id(order.id, actor: %{admin: true})
    end

    test "system actor can still read a placed order", %{order: order} do
      assert {:ok, _} = Order.get_by_id(order.id, actor: %{system: true})
    end
  end

  describe "LineItem is immutable when parent order is :placed" do
    setup do
      tax_rate = generate(tax_rate())
      product = generate(product(tax_rate_id: tax_rate.id))
      variant = generate(product_variant(product_id: product.id))

      placed_order =
        generate(
          order(
            state: :placed,
            payment_status: :paid,
            payment_intent_id: "pi_test",
            ordered_at: DateTime.utc_now()
          )
        )

      line_item =
        generate(
          line_item(
            order_id: placed_order.id,
            product_variant_id: variant.id
          )
        )

      {:ok, order: placed_order, variant: variant, line_item: line_item}
    end

    test "guest cannot add a line item to a placed order", %{order: order, variant: variant} do
      assert {:error, %Ash.Error.Forbidden{}} =
               LineItem
               |> Ash.Changeset.for_create(
                 :add_to_cart,
                 %{order_id: order.id, product_variant_id: variant.id, quantity: 1},
                 actor: nil
               )
               |> Ash.create(actor: nil)
    end

    test "admin cannot add a line item to a placed order", %{order: order, variant: variant} do
      assert {:error, %Ash.Error.Forbidden{}} =
               LineItem
               |> Ash.Changeset.for_create(
                 :add_to_cart,
                 %{order_id: order.id, product_variant_id: variant.id, quantity: 1},
                 actor: %{admin: true}
               )
               |> Ash.create(actor: %{admin: true})
    end

    test "admin cannot increment quantity on a placed order's line item", %{line_item: line_item} do
      assert {:error, %Ash.Error.Forbidden{}} =
               line_item
               |> Ash.Changeset.for_update(:increment_quantity, %{}, actor: %{admin: true})
               |> Ash.update(actor: %{admin: true})
    end

    test "admin cannot destroy a placed order's line item", %{line_item: line_item} do
      assert {:error, %Ash.Error.Forbidden{}} =
               line_item
               |> Ash.Changeset.for_destroy(:remove_item, %{}, actor: %{admin: true})
               |> Ash.destroy(actor: %{admin: true})
    end

    test "owner cannot mutate their own placed order's line item", %{line_item: line_item, order: order} do
      # Owner reads are allowed; writes are not.
      owner = %{id: order.user_id || Ash.UUID.generate()}

      assert {:error, %Ash.Error.Forbidden{}} =
               line_item
               |> Ash.Changeset.for_update(:increment_quantity, %{}, actor: owner)
               |> Ash.update(actor: owner)
    end
  end
end
