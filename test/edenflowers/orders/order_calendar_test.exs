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

    # It would repeat on a weekday the shop is closed.
    test "submit_delivery refuses a subscription's first delivery on a date opened outside the weekdays" do
      pickup_option = generate(fulfillment_option(fulfillment_method: :pickup))
      special = Date.add(Edenflowers.ShopTime.today(), 7)
      shop_calendar(available_days: [], enabled_dates: [special])

      submit = fn order ->
        order
        |> Ash.Changeset.for_update(:submit_delivery, %{
          fulfillment_option_id: pickup_option.id,
          fulfillment_date: special,
          contact_phone_number: "045 1234567"
        })
        |> Ash.update(authorize?: false)
      end

      one_off = generate(order(state: :delivery))

      Edenflowers.Orders.add_line_item!(one_off.id, generate(product_variant(product_id: generate(product()).id)).id, 1,
        authorize?: false
      )

      assert {:ok, _order} = submit.(one_off)

      subscribable = generate(product_variant(product_id: generate(product(subscribable: true)).id))
      subscription = generate(order(state: :delivery))
      Edenflowers.Orders.add_line_item!(subscription.id, subscribable.id, 1, %{interval_weeks: 2}, authorize?: false)
      assert {:error, %Ash.Error.Invalid{errors: errors}} = submit.(subscription)
      assert Enum.any?(errors, &(&1.field == :fulfillment_date))
    end

    test "Available from names the first open day when the shop is closed on it" do
      available_from = Date.add(Edenflowers.ShopTime.today(), 3)
      shop_calendar(disabled_dates: [available_from, Date.add(available_from, 1)])
      first_open_day = Date.add(available_from, 2)

      product = generate(product(available_from: available_from))
      variant = generate(product_variant(product_id: product.id))
      order = generate(order(state: :delivery))
      Edenflowers.Orders.add_line_item!(order.id, variant.id, 1, authorize?: false)

      assert Ash.load!(product, :first_open_day, authorize?: false).first_open_day == first_open_day
      assert Ash.load!(order, :first_open_day, authorize?: false).first_open_day == first_open_day
    end
  end
end
