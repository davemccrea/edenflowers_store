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
  end
end
