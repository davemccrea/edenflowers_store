defmodule Edenflowers.Fulfillment do
  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  resources do
    resource Edenflowers.Fulfillment.FulfillmentOption
    resource Edenflowers.Fulfillment.ProductFulfillmentOption
    resource Edenflowers.Fulfillment.OpeningHours
  end
end
