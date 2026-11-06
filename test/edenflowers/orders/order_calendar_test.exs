defmodule Edenflowers.Orders.OrderCalendarTest do
  use Edenflowers.DataCase, async: false

  import Generator

  describe "Order Step 3 - Fulfillment and delivery" do
    test "save_step_3 rejects a date the shop has closed" do
      pickup_option =
        generate(
          fulfillment_option(
            name: "Store Pickup",
            fulfillment_method: :pickup,
            rate_type: :fixed,
            base_price: "5.00"
          )
        )

      order = generate(order(state: :delivery))
      closed_date = Date.add(Edenflowers.ShopTime.today(), 3)

      shop_calendar(disabled_dates: [closed_date])

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               order
               |> Ash.Changeset.for_update(:submit_delivery, %{
                 fulfillment_option_id: pickup_option.id,
                 fulfillment_date: closed_date,
                 contact_phone_number: "045 1234567"
               })
               |> Ash.update(authorize?: false)

      assert Enum.any?(errors, &(&1.field == :fulfillment_date))
    end

    test "submit_delivery refuses a day before a product's Available from, and takes that day" do
      pickup_option = generate(fulfillment_option(fulfillment_method: :pickup))
      available_from = Date.add(Edenflowers.ShopTime.today(), 3)
      product = generate(product(available_from: available_from))
      variant = generate(product_variant(product_id: product.id))
      order = generate(order(state: :delivery))
      Edenflowers.Orders.add_line_item!(order.id, variant.id, 1, authorize?: false)

      submit = fn date ->
        order
        |> Ash.Changeset.for_update(:submit_delivery, %{
          fulfillment_option_id: pickup_option.id,
          fulfillment_date: date,
          contact_phone_number: "045 1234567"
        })
        |> Ash.update(authorize?: false)
      end

      assert {:error, %Ash.Error.Invalid{errors: errors}} = submit.(Date.add(available_from, -1))
      assert Enum.any?(errors, &(&1.field == :fulfillment_date))
      assert {:ok, _order} = submit.(available_from)
    end
  end
end
