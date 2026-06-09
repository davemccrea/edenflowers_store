defmodule Edenflowers.Pricing do
  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  resources do
    resource Edenflowers.Pricing.TaxRate
    resource Edenflowers.Pricing.Promotion
  end
end
