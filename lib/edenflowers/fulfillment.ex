defmodule Edenflowers.Fulfillment do
  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  resources do
    resource Edenflowers.Fulfillment.FulfillmentOption do
      define :list_options, action: :read
      define :list_options_for_checkout, action: :list_for_checkout
      define :get_option_by_id, action: :by_id, args: [:id]
      define :update_calendar, action: :update_calendar
      define :toggle_date, action: :toggle_date, args: [:date]
      define :set_weekday, action: :set_weekday, args: [:weekday, :direction]
      define :set_week, action: :set_week, args: [:week, :today, :direction]
      define :reset_calendar, action: :reset_calendar
      define :calculate_price, action: :calculate_price, args: [:fulfillment_option_id, :distance]
      define :calculate_delivery, action: :calculate_delivery, args: [:delivery_address, :fulfillment_option_id]
      define :fulfill_on_date, action: :fulfill_on_date, args: [:fulfillment_option_id, :date]
    end

    resource Edenflowers.Fulfillment.ProductFulfillmentOption
    resource Edenflowers.Fulfillment.OpeningHours
  end
end
