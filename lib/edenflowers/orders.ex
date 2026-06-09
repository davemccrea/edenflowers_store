defmodule Edenflowers.Orders do
  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  resources do
    resource Edenflowers.Orders.Order
    resource Edenflowers.Orders.LineItem
  end
end
